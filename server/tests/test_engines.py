import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from sklearn.metrics import cohen_kappa_score

from app import agreement, config, matching, rubric, suggest
from app.catalogue import Catalogue


def _cat():
    c = Catalogue().load()
    return c


def test_matching_heldout_accuracy():
    cat = _cat()
    eng = matching.MappingEngine().build(cat, matching.load_examples(config.EXAMPLES_DIR / "declarations_train.csv"))
    test = matching.load_examples(config.EXAMPLES_DIR / "declarations_test.csv")
    top1 = sum(eng.rank(r["text"], 1)["matches"][0]["qp_code"] == r["qp_code"] for r in test)
    assert top1 / len(test) >= 0.85


def test_matching_ambiguous_is_not_high_confidence():
    cat = _cat()
    eng = matching.MappingEngine().build(cat, [])
    r = eng.rank("pipe welding and fitting of water lines", 3)
    assert r["confidence"] != "high" or r["margin"] < 3


def test_weighted_kappa_matches_sklearn():
    rnd = random.Random(7)
    a = [rnd.randint(0, 3) for _ in range(300)]
    b = [min(3, max(0, x + rnd.choice([-1, 0, 0, 1]))) for x in a]
    assert abs(agreement.weighted_kappa(a, b) - cohen_kappa_score(a, b, weights="quadratic")) < 1e-9
    assert agreement.weighted_kappa([1, 1, 1], [1, 1, 1]) is None


def test_agreement_report_modes_and_improvement():
    rnd = random.Random(3)
    rows = []
    for i in range(60):
        truth = rnd.randint(0, 3)
        for assessor, aids, noise in (("A", 1, 0), ("B", 1, 0), ("C", 0, 1), ("D", 0, 1)):
            pass
        # assisted pair: tiny noise; blind pair: bigger noise
        for assessor, aids, spread in (("A", True, 0), ("B", True, 1), ):
            pass
    for i in range(80):
        t = rnd.randint(0, 3)
        clamp = lambda v: min(3, max(0, v))
        rows += [{"assessment_id": f"x{i}", "criterion_id": "c", "assessor_id": "A", "score": t, "aids_shown": 1},
                 {"assessment_id": f"x{i}", "criterion_id": "c", "assessor_id": "B", "score": clamp(t + rnd.choice([0, 0, 0, 1])), "aids_shown": 1},
                 {"assessment_id": f"y{i}", "criterion_id": "c", "assessor_id": "A", "score": t, "aids_shown": 0},
                 {"assessment_id": f"y{i}", "criterion_id": "c", "assessor_id": "B", "score": clamp(t + rnd.choice([-2, -1, 0, 1, 2])), "aids_shown": 0}]
    rep = agreement.agreement_report(rows)
    assert rep["assisted"]["n_pairs"] == 80 and rep["unassisted"]["n_pairs"] == 80
    assert rep["kappa_improvement"] > 0
    assert rep["assisted"]["icc"] > rep["unassisted"]["icc"]


def test_every_criterion_has_rubric_inputs():
    cat = _cat()
    for cid, ctx in cat.criteria.items():
        c = ctx["criterion"]
        assert len(c["indicators"]) >= 3, cid
        assert all(i["kw"] for i in c["indicators"]), cid
        assert c["text"].get("hi") and c["task"].get("hi"), cid


def test_suggest_caps_and_languages():
    cat = _cat()
    c = cat.get_criterion("WLD-N2-C2")["criterion"]
    full = "I use E6013 electrode at 110 amps, keep short arc length and steady travel speed for a uniform bead, welding flat and horizontal with root and cap pass"
    assert suggest.suggest(c, full, 0)["suggested_score"] == 2        # capped: video evidence needed
    assert suggest.suggest(c, full, 1)["suggested_score"] == 3
    assert suggest.suggest(c, "", 0)["suggested_score"] == 0
    hi = cat.get_criterion("PLB-N1-C1")["criterion"]
    assert suggest.suggest(hi, "पहले मैं मेन वाल्व बंद करता हूँ, दस्ताने और चश्मा पहनता हूँ, फर्श ढकता हूँ", 0)["suggested_score"] >= 2


def test_rubric_thresholds():
    cat = _cat()
    qp = cat.get("KS-MSN-L3")
    ids = [c["id"] for n in qp["nos"] for c in n["criteria"]]
    assert rubric.compute_profile(qp, {i: 3 for i in ids})["recommendation"]["code"] == "recommend_certification"
    assert rubric.compute_profile(qp, {i: 0 for i in ids})["recommendation"]["code"] == "not_yet_competent"
    assert rubric.compute_profile(qp, {})["recommendation"]["code"] == "incomplete"
    mixed = {i: 2 for i in ids}
    assert rubric.compute_profile(qp, mixed)["recommendation"]["code"] in ("partial_gap_training", "recommend_certification")
