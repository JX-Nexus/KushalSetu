"""Measure QP-mapping accuracy on a labelled CSV (text,language,qp_code). Default: held-out test split."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from app import config, matching  # noqa: E402
from app.catalogue import Catalogue  # noqa: E402

cat = Catalogue().load()
eng = matching.MappingEngine().build(cat, matching.load_examples(config.EXAMPLES_DIR / "declarations_train.csv"))
path = Path(sys.argv[1]) if len(sys.argv) > 1 else config.EXAMPLES_DIR / "declarations_test.csv"
rows = matching.load_examples(path)
t1 = t2 = 0
bad = []
for r in rows:
    codes = [m["qp_code"] for m in eng.rank(r["text"], 3)["matches"]]
    t1 += codes[:1] == [r["qp_code"]]
    t2 += r["qp_code"] in codes[:2]
    if codes[:1] != [r["qp_code"]]:
        bad.append((r["text"][:60], r["qp_code"], codes[0] if codes else None))
print(f"{path.name}: top-1 {t1}/{len(rows)} = {100*t1/max(len(rows),1):.1f}%   top-2 {t2}/{len(rows)}")
for b in bad:
    print("  miss:", b)
