"""Qualification-pack catalogue loaded from JSON files (the source of truth)."""
import hashlib
import json
import logging
from typing import Dict, List, Optional

from . import config

log = logging.getLogger("ks.catalogue")
LANGS = ("en", "hi", "mr")


def loc(d, lang: str) -> str:
    """Localised string with fallback chain: lang -> hi (for mr) -> en."""
    if isinstance(d, str):
        return d
    if not d:
        return ""
    chain = [lang]
    if lang == "mr":
        chain.append("hi")
    chain.append("en")
    for k in chain:
        if d.get(k):
            return d[k]
    return next(iter(d.values()), "")


class Catalogue:
    def __init__(self):
        self.packs: Dict[str, dict] = {}
        self.criteria: Dict[str, dict] = {}   # criterion id -> {criterion, nos, qp}
        self.version = "empty"

    def load(self) -> "Catalogue":
        packs, crit = {}, {}
        files = sorted(config.CATALOGUE_DIR.glob("*.json"))
        for f in files:
            try:
                qp = json.loads(f.read_text(encoding="utf-8"))
                self._validate(qp, f.name)
            except Exception as e:  # a bad file must not take the server down
                log.error("Skipping %s: %s", f.name, e)
                continue
            packs[qp["code"]] = qp
            for nos in qp["nos"]:
                for c in nos["criteria"]:
                    if c["id"] in crit:
                        log.error("Duplicate criterion id %s in %s", c["id"], f.name)
                        continue
                    crit[c["id"]] = {"criterion": c, "nos": nos, "qp": qp}
        self.packs, self.criteria = packs, crit
        h = hashlib.sha256()
        for f in files:
            h.update(f.read_bytes())
        self.version = h.hexdigest()[:12]
        log.info("Catalogue loaded: %d packs, %d criteria (v%s)", len(packs), len(crit), self.version)
        return self

    @staticmethod
    def _validate(qp: dict, name: str):
        for k in ("code", "title", "nos"):
            if k not in qp:
                raise ValueError(f"missing '{k}'")
        if not qp["nos"]:
            raise ValueError("no NOS")
        total = 0.0
        for n in qp["nos"]:
            if not n.get("criteria"):
                raise ValueError(f"NOS {n.get('code')} has no criteria")
            total += float(n.get("weight", 0))
            for c in n["criteria"]:
                if not c.get("id") or not c.get("text") or not c.get("task"):
                    raise ValueError(f"criterion incomplete in {n.get('code')}")
        if abs(total - 1.0) > 0.01:
            raise ValueError(f"NOS weights sum to {total}, expected 1.0")

    # ---- views -------------------------------------------------------------
    def get(self, code: str) -> Optional[dict]:
        return self.packs.get(code)

    def get_criterion(self, cid: str) -> Optional[dict]:
        return self.criteria.get(cid)

    def summary(self, lang: str = "en") -> List[dict]:
        return [self.pack_summary(qp, lang) for qp in self.packs.values()]

    def pack_summary(self, qp: dict, lang: str = "en") -> dict:
        return {
            "code": qp["code"], "official_code": qp.get("official_code"), "verified": qp.get("verified", False),
            "title": loc(qp["title"], lang), "sector": qp.get("sector", ""), "nsqf_level": qp.get("nsqf_level"),
            "description": loc(qp.get("description", {}), lang),
            "nos_count": len(qp["nos"]),
            "criteria_count": sum(len(n["criteria"]) for n in qp["nos"]),
            "source_note": qp.get("source_note", ""),
        }

    def checklist(self, code: str, lang: str = "en") -> Optional[dict]:
        """Practical task checklist generated from the pack's NOS/criteria."""
        qp = self.packs.get(code)
        if not qp:
            return None
        out = self.pack_summary(qp, lang)
        out["nos"] = []
        for n in qp["nos"]:
            out["nos"].append({
                "code": n["code"], "title": loc(n["title"], lang), "weight": n["weight"],
                "pass_threshold": n.get("pass_threshold", 0.6),
                "criteria": [{
                    "id": c["id"], "text": loc(c["text"], lang), "task": loc(c["task"], lang),
                    "critical": bool(c.get("critical")), "weight": c.get("weight", 1),
                    "evidence": c.get("evidence", "none"),
                    "indicators": [i["en"] for i in c.get("indicators", [])],
                } for c in n["criteria"]],
            })
        return out

    def export_full(self) -> dict:
        """Everything the mobile app needs to work offline (incl. matching vocabulary)."""
        return {"version": self.version, "packs": list(self.packs.values())}


catalogue = Catalogue()
