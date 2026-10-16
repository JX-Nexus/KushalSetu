"""Inter-assessor agreement statistics (the 'consistency evidence')."""
import itertools
from collections import defaultdict
from typing import Dict, List, Optional, Sequence

import numpy as np

K = 4  # scale 0..3


def weighted_kappa(a: Sequence[int], b: Sequence[int], k: int = K, weights: str = "quadratic") -> Optional[float]:
    a = np.asarray(a, dtype=int)
    b = np.asarray(b, dtype=int)
    n = len(a)
    if n == 0:
        return None
    obs = np.zeros((k, k))
    for i, j in zip(a, b):
        obs[i, j] += 1
    obs /= n
    exp = np.outer(obs.sum(1), obs.sum(0))
    idx = np.arange(k)
    d = np.abs(idx[:, None] - idx[None, :]).astype(float)
    w = d ** 2 if weights == "quadratic" else d
    denom = (w * exp).sum()
    if denom == 0:
        return None            # undefined: no variation in ratings
    return float(1.0 - (w * obs).sum() / denom)


def icc_1_1(pairs: List[Sequence[int]]) -> Optional[float]:
    """One-way random-effects ICC(1,1) for targets rated by exactly 2 raters."""
    if len(pairs) < 3:
        return None
    x = np.asarray(pairs, dtype=float)
    n, k = x.shape
    grand = x.mean()
    msb = k * ((x.mean(1) - grand) ** 2).sum() / (n - 1)
    msw = ((x - x.mean(1, keepdims=True)) ** 2).sum() / (n * (k - 1))
    denom = msb + (k - 1) * msw
    if denom == 0:
        return None
    return float((msb - msw) / denom)


def _stats(pairs: List[tuple]) -> dict:
    if not pairs:
        return {"n_pairs": 0, "exact_agreement_pct": None, "within_one_pct": None, "mean_abs_diff": None,
                "weighted_kappa": None, "icc": None}
    a = [p[0] for p in pairs]
    b = [p[1] for p in pairs]
    diff = np.abs(np.array(a) - np.array(b))
    kap = weighted_kappa(a, b)
    icc = icc_1_1([(x, y) for x, y in pairs])
    return {
        "n_pairs": len(pairs),
        "exact_agreement_pct": round(float((diff == 0).mean() * 100), 1),
        "within_one_pct": round(float((diff <= 1).mean() * 100), 1),
        "mean_abs_diff": round(float(diff.mean()), 3),
        "weighted_kappa": None if kap is None else round(kap, 3),
        "icc": None if icc is None else round(icc, 3),
    }


def agreement_report(score_rows: List[dict], ai_rows: Optional[List[dict]] = None, min_pairs: int = 10) -> dict:
    """score_rows: {assessment_id, criterion_id, assessor_id, score, aids_shown}
    ai_rows: {assessment_id, criterion_id, ai_score}"""
    groups: Dict[tuple, List[dict]] = defaultdict(list)
    for r in score_rows:
        groups[(r["assessment_id"], r["criterion_id"])].append(r)
    assisted, unassisted = [], []
    for rows in groups.values():
        for r1, r2 in itertools.combinations(sorted(rows, key=lambda r: r["assessor_id"]), 2):
            if bool(r1["aids_shown"]) and bool(r2["aids_shown"]):
                assisted.append((r1["score"], r2["score"]))
            elif not r1["aids_shown"] and not r2["aids_shown"]:
                unassisted.append((r1["score"], r2["score"]))
    a, u = _stats(assisted), _stats(unassisted)

    ai_cmp = None
    if ai_rows:
        ai_map = {(r["assessment_id"], r["criterion_id"]): r["ai_score"] for r in ai_rows if r["ai_score"] is not None}
        pairs = [(ai_map[(r["assessment_id"], r["criterion_id"])], r["score"]) for r in score_rows
                 if (r["assessment_id"], r["criterion_id"]) in ai_map]
        ai_cmp = _stats(pairs)

    improvement = None
    caveat = []
    if a["weighted_kappa"] is not None and u["weighted_kappa"] is not None:
        improvement = round(a["weighted_kappa"] - u["weighted_kappa"], 3)
    else:
        caveat.append("Need double-scored items in BOTH modes (aids shown vs blind) to compare.")
    if min(a["n_pairs"], u["n_pairs"]) < min_pairs:
        caveat.append(f"Fewer than {min_pairs} score pairs in at least one mode: treat the comparison as indicative only.")
    return {"assisted": a, "unassisted": u, "kappa_improvement": improvement,
            "ai_vs_assessor": ai_cmp, "scale": "0-3 anchored rubric, quadratic weighted kappa", "caveats": caveat}
