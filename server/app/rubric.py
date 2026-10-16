"""Standardised scoring: anchored 0-3 scale -> NOS scores -> competency profile -> recommendation."""
import math
from typing import Dict, List, Optional

from .catalogue import loc

PASS_NOS_DEFAULT = 0.60      # weighted mean / 3
CERTIFY_OVERALL = 0.70
PARTIAL_OVERALL = 0.50
CRITICAL_MIN_SCORE = 2

RECOMMENDATION_LABELS = {
    "incomplete": "Assessment incomplete - not all criteria are scored",
    "recommend_certification": "Recommended for certification at the mapped NSQF level (pending assessor sign-off)",
    "partial_gap_training": "Partially competent - recommend bridge training on the gaps listed (pending assessor sign-off)",
    "not_yet_competent": "Not yet recommended - substantial gaps (pending assessor sign-off)",
}


def round_half_up(x: float) -> int:
    return int(math.floor(x + 0.5))


def consensus(scores_by_assessor: Dict[str, int]) -> Optional[int]:
    if not scores_by_assessor:
        return None
    vals = list(scores_by_assessor.values())
    return round_half_up(sum(vals) / len(vals))


def compute_profile(qp: dict, scores: Dict[str, int], lang: str = "en") -> dict:
    nos_out: List[dict] = []
    total_scored = total_crit = 0
    overall = 0.0
    gaps: List[str] = []
    all_pass = True
    any_pass = False
    for n in qp["nos"]:
        wsum = 0.0
        acc = 0.0
        rows = []
        crit_fail = False
        for c in n["criteria"]:
            total_crit += 1
            s = scores.get(c["id"])
            w = float(c.get("weight", 1))
            if s is not None:
                total_scored += 1
                acc += w * s
                wsum += w
                if c.get("critical") and s < CRITICAL_MIN_SCORE:
                    crit_fail = True
                if s < 2:
                    gaps.append(loc(c["text"], lang))
            rows.append({"criterion_id": c["id"], "text": loc(c["text"], lang), "critical": bool(c.get("critical")),
                         "score": s})
        complete = all(r["score"] is not None for r in rows)
        pct = (acc / wsum) / 3.0 if wsum else 0.0
        thr = float(n.get("pass_threshold", PASS_NOS_DEFAULT))
        passed = complete and pct >= thr and not crit_fail
        all_pass = all_pass and passed
        any_pass = any_pass or passed
        overall += float(n["weight"]) * pct
        nos_out.append({"nos_code": n["code"], "title": loc(n["title"], lang), "weight": n["weight"],
                        "score_pct": round(pct * 100, 1), "pass_threshold_pct": round(thr * 100, 1),
                        "passed": passed, "critical_failure": crit_fail, "complete": complete, "criteria": rows})
    complete = total_scored == total_crit and total_crit > 0
    if not complete:
        code = "incomplete"
    elif all_pass and overall >= CERTIFY_OVERALL:
        code = "recommend_certification"
    elif overall >= PARTIAL_OVERALL and any_pass:
        code = "partial_gap_training"
    else:
        code = "not_yet_competent"
    return {
        "qp_code": qp["code"], "qp_title": loc(qp["title"], lang), "nsqf_level": qp.get("nsqf_level"),
        "overall_pct": round(overall * 100, 1), "scored": total_scored, "total": total_crit, "complete": complete,
        "nos": nos_out, "gaps": gaps,
        "recommendation": {"code": code, "label": RECOMMENDATION_LABELS[code],
                           "binding": False,
                           "note": "Decision support only. The human assessor makes the final decision."},
    }
