"""Convert an official-style Qualification Pack CSV into the JSON format the server loads.

CSV columns (one row per criterion):
 qp_code,qp_title,sector,nsqf_level,official_code,nos_code,nos_title,nos_weight,criterion_id,
 criterion_text,task,indicators,keywords,evidence,critical
 - indicators: observable look-fors separated by '|'
 - keywords:   matching words for ALL indicators of the row, separated by '|' (any language / romanised)
 - evidence:   photo | video | none     critical: 1 or 0
Usage: python scripts/import_qp_csv.py my_qp.csv        (writes data/qualification_packs/<code>.json)
"""
import csv
import json
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "qualification_packs"


def main(path):
    packs = {}
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            qp = packs.setdefault(r["qp_code"], {
                "code": r["qp_code"], "official_code": r.get("official_code") or None, "verified": True,
                "source_note": "Imported from CSV", "title": {"en": r["qp_title"]}, "sector": r.get("sector", ""),
                "nsqf_level": int(r["nsqf_level"] or 0), "description": {"en": r["qp_title"]},
                "keywords": {"en": [], "hi": [], "mr": [], "rom": []}, "nos": []})
            nos = next((n for n in qp["nos"] if n["code"] == r["nos_code"]), None)
            if not nos:
                nos = {"code": r["nos_code"], "title": {"en": r["nos_title"]}, "weight": float(r.get("nos_weight") or 0),
                       "pass_threshold": 0.6, "criteria": []}
                qp["nos"].append(nos)
            kws = [k.strip() for k in (r.get("keywords") or "").split("|") if k.strip()]
            inds = [i.strip() for i in (r.get("indicators") or "").split("|") if i.strip()]
            nos["criteria"].append({
                "id": r["criterion_id"], "critical": r.get("critical", "0") in ("1", "true", "True"), "weight": 1,
                "text": {"en": r["criterion_text"]}, "task": {"en": r["task"]},
                "indicators": [{"en": i, "kw": kws} for i in inds], "evidence": r.get("evidence") or "none"})
            qp["keywords"]["en"].extend(kws)
    for qp in packs.values():
        if all(n["weight"] == 0 for n in qp["nos"]):          # equal weights if not supplied
            for n in qp["nos"]:
                n["weight"] = round(1 / len(qp["nos"]), 4)
        tot = sum(n["weight"] for n in qp["nos"])
        for n in qp["nos"]:
            n["weight"] = round(n["weight"] / tot, 4)
        OUT.mkdir(parents=True, exist_ok=True)
        fp = OUT / (qp["code"].lower().replace("/", "_").replace("-", "_") + ".json")
        fp.write_text(json.dumps(qp, ensure_ascii=False, indent=1), encoding="utf-8")
        print("wrote", fp)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
