"""Import double-scored assessments (e.g. the organisers' dummy data) so /api/analytics/agreement can report kappa.
CSV columns: assessment_id,criterion_id,assessor_username,score,aids_shown(1/0)
The assessments and assessors must already exist (assessors are created from KS_ASSESSORS)."""
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from app import db  # noqa: E402

if len(sys.argv) != 2:
    sys.exit(__doc__)
db.init_db()
n = skipped = 0
with db.session() as conn, open(sys.argv[1], newline="", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        u = conn.execute("SELECT id FROM users WHERE username=?", (r["assessor_username"],)).fetchone()
        a = conn.execute("SELECT id FROM assessments WHERE id=?", (r["assessment_id"],)).fetchone()
        if not u or not a or not (0 <= int(r["score"]) <= 3):
            skipped += 1
            continue
        t = db.now()
        conn.execute("""INSERT INTO assessor_scores(assessment_id,criterion_id,assessor_id,score,aids_shown,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?) ON CONFLICT(assessment_id,criterion_id,assessor_id)
                        DO UPDATE SET score=excluded.score, aids_shown=excluded.aids_shown, updated_at=excluded.updated_at""",
                     (r["assessment_id"], r["criterion_id"], u["id"], int(r["score"]), int(r.get("aids_shown", 1) or 1), t, t))
        n += 1
print(f"imported {n} scores, skipped {skipped}")
