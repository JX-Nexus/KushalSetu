"""Optional LLM enrichment (Gemini cloud or a local Ollama server).

Safeguards: the LLM never changes a score or a decision. Its output is stored beside the
rule-based suggestion as an extra explanation / image observation for the assessor, and every
failure degrades silently to the rule-based result.
"""
import base64
import json
import logging
import re
from typing import List, Optional

import httpx

from . import config

log = logging.getLogger("ks.llm")


def status() -> dict:
    if config.GEMINI_API_KEY:
        return {"provider": "gemini", "model": config.GEMINI_MODEL, "available": True, "vision": True}
    if config.OLLAMA_URL:
        ok = False
        try:
            ok = httpx.get(f"{config.OLLAMA_URL}/api/tags", timeout=2.0).status_code == 200
        except Exception:
            pass
        return {"provider": "ollama", "model": config.OLLAMA_MODEL, "available": ok, "vision": False}
    return {"provider": None, "model": None, "available": False, "vision": False}


def _extract_json(text: str) -> Optional[dict]:
    if not text:
        return None
    text = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.M).strip()
    try:
        return json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text, flags=re.S)
        if m:
            try:
                return json.loads(m.group(0))
            except Exception:
                return None
    return None


def _call(prompt: str, image: Optional[tuple] = None) -> Optional[dict]:
    """image = (mime, bytes). Returns parsed JSON dict or None."""
    try:
        if config.GEMINI_API_KEY:
            parts: List[dict] = [{"text": prompt}]
            if image:
                parts.append({"inline_data": {"mime_type": image[0], "data": base64.b64encode(image[1]).decode()}})
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{config.GEMINI_MODEL}:generateContent"
            r = httpx.post(url, params={"key": config.GEMINI_API_KEY}, timeout=config.LLM_TIMEOUT,
                           json={"contents": [{"parts": parts}],
                                 "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json"}})
            r.raise_for_status()
            txt = r.json()["candidates"][0]["content"]["parts"][0]["text"]
            return _extract_json(txt)
        if config.OLLAMA_URL and not image:
            r = httpx.post(f"{config.OLLAMA_URL}/api/generate", timeout=config.LLM_TIMEOUT,
                           json={"model": config.OLLAMA_MODEL, "prompt": prompt, "stream": False, "format": "json",
                                 "options": {"temperature": 0.1}})
            r.raise_for_status()
            return _extract_json(r.json().get("response", ""))
    except Exception as e:
        log.warning("LLM call failed: %s", e)
    return None


def review_answer(criterion_text: str, task: str, indicators: List[str], answer: str, language: str) -> Optional[dict]:
    if not (answer or "").strip():
        return None
    prompt = (
        "You support a vocational skill assessor (Recognition of Prior Learning, India). "
        "Judge ONLY what the worker wrote; self-reported experience is not proof of skill.\n"
        f"Competency: {criterion_text}\nTask asked: {task}\nObservable indicators:\n- " + "\n- ".join(indicators) +
        f"\nWorker answer ({language}): {answer}\n"
        'Return JSON only: {"suggested_score": 0-3 integer (0 none,1 partial,2 minor guidance,3 independent), '
        '"observed": [indicators clearly shown], "missing": [indicators not shown], '
        '"rationale": "2 short sentences in English", "follow_up_question": "one question the assessor should ask"}'
    )
    d = _call(prompt)
    if not isinstance(d, dict):
        return None
    try:
        s = int(d.get("suggested_score"))
        if not 0 <= s <= 3:
            return None
    except Exception:
        return None
    return {"provider": status()["provider"], "model": status()["model"], "suggested_score": s,
            "observed": [str(x) for x in d.get("observed", [])][:6],
            "missing": [str(x) for x in d.get("missing", [])][:6],
            "rationale": str(d.get("rationale", ""))[:600],
            "follow_up_question": str(d.get("follow_up_question", ""))[:300]}


def describe_image(path, mime: str, criterion_text: str, indicators: List[str]) -> Optional[dict]:
    if not config.GEMINI_API_KEY or not str(mime).startswith("image/"):
        return None
    try:
        data = open(path, "rb").read()
    except Exception:
        return None
    if len(data) > 8 * 1024 * 1024:
        return None
    prompt = (
        "You assist a trade assessor reviewing a photo submitted as evidence. Describe only what is visible. "
        f"Competency: {criterion_text}\nIndicators to look for:\n- " + "\n- ".join(indicators) +
        '\nReturn JSON only: {"relevant": true/false, "observations": ["..."], "indicators_visible": ["..."], '
        '"safety_concerns": ["..."], "image_quality": "good|poor"}. Do not give a score.'
    )
    d = _call(prompt, image=(mime, data))
    if not isinstance(d, dict):
        return None
    return {"provider": "gemini", "model": config.GEMINI_MODEL, "relevant": bool(d.get("relevant")),
            "observations": [str(x) for x in d.get("observations", [])][:6],
            "indicators_visible": [str(x) for x in d.get("indicators_visible", [])][:6],
            "safety_concerns": [str(x) for x in d.get("safety_concerns", [])][:4],
            "image_quality": str(d.get("image_quality", ""))[:10]}
