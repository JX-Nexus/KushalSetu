"""Assessor-support score suggestions against anchored rubrics.

The suggestion is computed (not canned): each criterion carries observable indicators with
multilingual keyword anchors; the worker's answer is matched against them (typo tolerant),
then banded onto the standard 0-3 scale. Practical evidence caps what a written answer can earn.
The assessor always makes the final score.
"""
import difflib
import re
from typing import Dict, List

from .matching import content_tokens, normalize

ANCHORS = {
    0: {"label": "Not demonstrated", "hi": "प्रदर्शित नहीं",
        "descriptor": "No relevant knowledge or practice shown; or unsafe approach."},
    1: {"label": "Partial / needs close supervision", "hi": "आंशिक / निगरानी की ज़रूरत",
        "descriptor": "Knows some steps but misses key ones; needs close supervision."},
    2: {"label": "Competent with minor guidance", "hi": "थोड़े मार्गदर्शन से सक्षम",
        "descriptor": "Performs most steps correctly; occasional prompts needed."},
    3: {"label": "Independent, to standard", "hi": "स्वतंत्र, मानक के अनुसार",
        "descriptor": "Performs all key steps correctly, safely and independently."},
}

_ASCII_WORD = re.compile(r"^[a-z]+$")


def _kw_hit(kw: str, text: str, tokens: List[str]) -> bool:
    k = normalize(kw).strip()
    if not k:
        return False
    if not _ASCII_WORD.match(k):          # phrases, numbers, Devanagari -> substring
        return k in text
    if len(k) <= 3:                        # short acronyms: exact token only (mcb, gi, ppr)
        return k in tokens
    stem = k[:-1] if len(k) >= 6 else k
    for t in tokens:
        if t == k or t.startswith(stem):
            return True
        if len(t) >= 5 and difflib.SequenceMatcher(None, t, k).ratio() >= 0.86:
            return True
    return False


def match_indicators(criterion: dict, answer: str) -> List[dict]:
    text = normalize(answer)
    tokens = re.findall(r"[a-z0-9]+", text)
    out = []
    for ind in criterion.get("indicators", []):
        hits = [kw for kw in ind.get("kw", []) if _kw_hit(kw, text, tokens)]
        out.append({"indicator": ind["en"], "matched": bool(hits), "evidence_terms": hits[:4]})
    return out


def suggest(criterion: dict, answer: str, evidence_count: int = 0) -> dict:
    answer = (answer or "").strip()
    words = len(content_tokens(answer))
    ind = match_indicators(criterion, answer)
    n = max(len(ind), 1)
    hits = sum(1 for i in ind if i["matched"])
    cov = hits / n

    if hits == 0:
        base = 0
    elif cov <= 0.34:
        base = 1
    elif cov <= 0.67:
        base = 2
    else:
        base = 3

    caps = []
    score = base
    if words < 6 and score > 1:
        score = 1
        caps.append("Answer is very short; detail is needed to score higher.")
    needs_evidence = criterion.get("evidence", "none") != "none"
    if needs_evidence and evidence_count == 0 and score > 2:
        score = 2
        caps.append("A written answer alone cannot earn level 3 here; practical evidence "
                    f"({criterion.get('evidence')}) or assessor observation is required.")

    edge = min(abs(cov - 0.34), abs(cov - 0.67)) if 0 < hits < n else 0.17
    confidence = round(min(0.95, 0.30 + 0.40 * min(words / 30.0, 1.0) + 0.30 * min(edge / 0.17, 1.0)), 2)

    matched = [i["indicator"] for i in ind if i["matched"]]
    missing = [i["indicator"] for i in ind if not i["matched"]]
    if not answer:
        rationale = "No written answer was provided."
    else:
        rationale = (f"{hits} of {n} observable indicators were mentioned in the answer"
                     f" ({'; '.join(matched) if matched else 'none'}).")
        if missing:
            rationale += f" Not mentioned: {'; '.join(missing)}."
        rationale += " " + " ".join(caps)
    return {
        "engine": "rubric_indicator_matcher_v1",
        "suggested_score": score, "confidence": confidence,
        "indicators": ind, "matched": matched, "missing": missing,
        "answer_words": words, "evidence_count": evidence_count,
        "capped": bool(caps), "rationale": rationale.strip(),
        "needs_assessor_attention": bool(criterion.get("critical")) or confidence < 0.5,
    }
