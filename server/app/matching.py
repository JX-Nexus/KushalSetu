"""NSQF qualification-pack mapping engine.

Free-text self-declaration (English / Hindi / Marathi / romanised Hinglish, typos tolerated)
-> ranked qualification packs with similarity scores, matched terms and matched NOS.

Method: TF-IDF retrieval (word 1-2 grams + character 3-5 grams) over an index built from the
catalogue (titles, descriptions, multilingual keywords, NOS, criteria, indicator vocabulary) plus
labelled example declarations. No answers are hardcoded: the ranking is computed per request.
"""
import csv
import difflib
import logging
import re
import unicodedata
from typing import Dict, List, Optional

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer

from . import config
from .catalogue import Catalogue, loc

log = logging.getLogger("ks.matching")

_TOKEN_RE = re.compile(r"[\w\u0900-\u0963\u0966-\u097F]+", re.UNICODE)
STOP = set("""a an the i am is are was were be been being of to in on at for with and or but my me we you he she it
this that these those have has had do does did from by as into over under about than then so very also just
work works worked working job years year yrs since lot many some any all
है हूँ हूं हैं था थे थी का की के में और से को पर मैं मैने मेरा मेरी साल वर्ष करता करती करते हुआ हुए
मी आहे आणि चा ची चे मध्ये ते हा ही आहेत करतो करते वर्षे वर्ष
hu hun hai hain ka ki ke ko me mein main aur se par ek saal sal karta karti karte kam kaam""".split())


def normalize(text: str) -> str:
    return unicodedata.normalize("NFC", (text or "")).lower()


def tokenize(text: str) -> List[str]:
    return _TOKEN_RE.findall(normalize(text))


def content_tokens(text: str) -> List[str]:
    return [t for t in tokenize(text) if t not in STOP and not t.isdigit() and len(t) > 1]


def _flatten_loc(d) -> str:
    if isinstance(d, str):
        return d
    if isinstance(d, dict):
        return " ".join(str(v) for v in d.values() if v)
    return ""


def _kw_text(kw: dict) -> str:
    parts = []
    for lang_list in (kw or {}).values():
        parts.extend(lang_list)
    return " ".join(parts)


class MappingEngine:
    def __init__(self):
        self.codes: List[str] = []
        self.pack_docs: List[str] = []
        self.nos_index: Dict[str, List[dict]] = {}
        self.vocab: Dict[str, set] = {}
        self._wv: Optional[TfidfVectorizer] = None
        self._cv: Optional[TfidfVectorizer] = None
        self._wm = None
        self._cm = None
        self._nos_wv: Dict[str, np.ndarray] = {}
        self.n_examples = 0

    # ------------------------------------------------------------------ build
    def build(self, cat: Catalogue, examples: Optional[List[dict]] = None) -> "MappingEngine":
        examples = examples or []
        by_qp: Dict[str, List[str]] = {}
        for ex in examples:
            if ex["qp_code"] in cat.packs and ex.get("text"):
                by_qp.setdefault(ex["qp_code"], []).append(ex["text"])
        self.n_examples = sum(len(v) for v in by_qp.values())

        self.codes, self.pack_docs, self.nos_index, self.vocab = [], [], {}, {}
        corpus: List[str] = []
        for code, qp in cat.packs.items():
            kw = _kw_text(qp.get("keywords", {}))
            head = f"{_flatten_loc(qp['title'])} {_flatten_loc(qp.get('description'))}"
            nos_parts, nos_docs = [], []
            for n in qp["nos"]:
                crit_text = []
                for c in n["criteria"]:
                    crit_text.append(_flatten_loc(c["text"]))
                    crit_text.append(" ".join(" ".join(i.get("kw", [])) for i in c.get("indicators", [])))
                nd = f"{_flatten_loc(n['title'])} {' '.join(crit_text)}"
                nos_docs.append({"code": n["code"], "title": n["title"], "doc": nd})
                nos_parts.append(nd)
            ex_text = " ".join(by_qp.get(code, []))
            # keywords are repeated to up-weight declared vocabulary over long criterion text
            doc = f"{head} {kw} {kw} {kw} {ex_text} {ex_text} {' '.join(nos_parts)}"
            self.codes.append(code)
            self.pack_docs.append(doc)
            self.nos_index[code] = nos_docs
            self.vocab[code] = set(content_tokens(f"{head} {kw} {ex_text} {' '.join(nos_parts)}"))
            corpus.extend([doc] + [d["doc"] for d in nos_docs] + by_qp.get(code, []))

        tok = lambda s: content_tokens(s)
        self._wv = TfidfVectorizer(tokenizer=tok, token_pattern=None, lowercase=False,
                                   ngram_range=(1, 2), sublinear_tf=True, min_df=1)
        self._cv = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), sublinear_tf=True,
                                   preprocessor=normalize, min_df=1)
        if not self.codes:
            return self
        self._wv.fit(corpus)
        self._cv.fit(corpus)
        self._wm = self._wv.transform(self.pack_docs)
        self._cm = self._cv.transform(self.pack_docs)
        self._nos_wv = {}
        for code, docs in self.nos_index.items():
            self._nos_wv[code] = (self._wv.transform([d["doc"] for d in docs]),
                                  self._cv.transform([d["doc"] for d in docs]))
        log.info("Mapping index built: %d packs, %d example declarations", len(self.codes), self.n_examples)
        return self

    # ------------------------------------------------------------------ query
    def _expand_typos(self, tokens: List[str]) -> List[str]:
        """Append the closest vocabulary word for tokens that are not known (typo tolerance)."""
        all_vocab = set().union(*self.vocab.values()) if self.vocab else set()
        extra = []
        for t in tokens:
            if t in all_vocab or len(t) < 5 or not t.isascii():
                continue
            m = difflib.get_close_matches(t, all_vocab, n=1, cutoff=0.82)
            if m:
                extra.append(m[0])
        return extra

    def rank(self, text: str, top_k: int = 3) -> dict:
        text = (text or "").strip()
        toks = content_tokens(text)
        if not self.codes or not toks:
            return {"matches": [], "confidence": "none", "reason": "empty_declaration", "query_terms": []}
        query = " ".join(toks + self._expand_typos(toks))
        qw = self._wv.transform([query])
        qc = self._cv.transform([query])
        word = (self._wm @ qw.T).toarray().ravel()
        char = (self._cm @ qc.T).toarray().ravel()
        raw = 0.6 * word + 0.4 * char
        total = float(raw.sum())
        order = np.argsort(-raw)

        qset = set(toks) | set(self._expand_typos(toks))
        matches = []
        for idx in order[:max(1, top_k)]:
            code = self.codes[idx]
            terms = sorted(qset & self.vocab[code], key=lambda t: (-len(t), t))[:8]
            nos_scores = self._nos_scores(code, qw, qc)
            matches.append({
                "qp_code": code,
                "score": round(float(raw[idx]), 4),
                "share": round(float(raw[idx]) / total, 4) if total > 0 else 0.0,
                "matched_terms": terms,
                "nos_relevance": nos_scores,
            })
        top = float(raw[order[0]])
        second = float(raw[order[1]]) if len(order) > 1 else 0.0
        margin = top / second if second > 1e-9 else float("inf")
        if top < 0.04 or not matches[0]["matched_terms"]:
            conf = "low"
        elif margin >= 1.6 and top >= 0.12:
            conf = "high"
        elif margin >= 1.2:
            conf = "medium"
        else:
            conf = "low"
        return {"matches": matches, "confidence": conf, "margin": None if margin == float("inf") else round(margin, 3),
                "query_terms": sorted(qset)[:20], "reason": None}

    def _nos_scores(self, code: str, qw, qc) -> List[dict]:
        wm, cm = self._nos_wv[code]
        s = 0.6 * (wm @ qw.T).toarray().ravel() + 0.4 * (cm @ qc.T).toarray().ravel()
        return [{"nos_code": d["code"], "score": round(float(v), 4)} for d, v in zip(self.nos_index[code], s)]


def load_examples(path) -> List[dict]:
    rows = []
    try:
        with open(path, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                rows.append({"text": r.get("text", ""), "language": r.get("language", ""), "qp_code": r.get("qp_code", "")})
    except FileNotFoundError:
        pass
    return rows


engine = MappingEngine()


def build_default(cat: Catalogue) -> MappingEngine:
    engine.build(cat, load_examples(config.EXAMPLES_DIR / "declarations_train.csv"))
    return engine
