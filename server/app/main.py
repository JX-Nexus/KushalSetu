"""KaushalSetu RPL assessment API (SIH26242).

Flow: worker self-declaration -> NSQF pack mapping -> generated practical checklist ->
evidence capture -> AI-assisted suggestions -> assessor scoring on an anchored rubric ->
competency profile + recommendation -> human sign-off. Offline clients push idempotent bundles.
"""
import hashlib
import json
import logging
import mimetypes
import os
import re
import uuid
from contextlib import asynccontextmanager
from typing import Dict, List, Optional

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response
from pydantic import BaseModel, Field

from . import config, db, llm, matching, rubric, suggest
from .agreement import agreement_report
from .catalogue import catalogue, loc
from .db import audit, get_db, loads, now
from .reports import build_pdf
from .security import (Principal, check_password, create_token, current_principal, hash_password,
                       require_assessor, verify_token)

log = logging.getLogger("ks.api")
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

VALID_LANGS = {"en", "hi", "mr"}
DECISIONS = {"certify", "partial", "not_yet", "more_evidence"}
REC_TO_DECISION = {"recommend_certification": "certify", "partial_gap_training": "partial",
                   "not_yet_competent": "not_yet"}
ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".mp4", ".mov", ".3gp", ".webm"}


# ------------------------------------------------------------------ startup
def seed_assessors():
    spec = os.getenv("KS_ASSESSORS", "").strip()
    with db.session() as conn:
        existing = conn.execute("SELECT COUNT(*) c FROM users WHERE role='assessor'").fetchone()["c"]
        entries = []
        if spec:
            for part in spec.split(","):
                bits = part.strip().split(":")
                if len(bits) >= 2:
                    entries.append((bits[0], bits[1], bits[2] if len(bits) > 2 else bits[0]))
        elif existing == 0 and os.getenv("KS_ENV", "dev") != "production":
            entries = [("assessor1", "assessor123", "Assessor One"), ("assessor2", "assessor123", "Assessor Two")]
            log.warning("No KS_ASSESSORS set: created DEV assessors assessor1/assessor2 (password 'assessor123'). "
                        "Set KS_ASSESSORS=user:pass:Name,... before any real use.")
        for user, pw, name in entries:
            row = conn.execute("SELECT id FROM users WHERE username=?", (user,)).fetchone()
            if row:
                conn.execute("UPDATE users SET password_hash=?, display_name=? WHERE id=?", (hash_password(pw), name, row["id"]))
            else:
                conn.execute("INSERT INTO users(id, role, username, password_hash, display_name, created_at) VALUES (?,?,?,?,?,?)",
                             (str(uuid.uuid4()), "assessor", user, hash_password(pw), name, now()))


@asynccontextmanager
async def lifespan(app: FastAPI):
    config.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    db.init_db()
    catalogue.load()
    matching.build_default(catalogue)
    seed_assessors()
    yield


app = FastAPI(title="KaushalSetu RPL API", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"], allow_credentials=False)


@app.exception_handler(Exception)
async def unhandled(request, exc):
    log.exception("Unhandled error on %s", request.url.path)
    return JSONResponse({"detail": "Internal server error"}, status_code=500)


# ------------------------------------------------------------------ models
class WorkerIn(BaseModel):
    id: str = Field(min_length=8, max_length=64)
    name: str = Field(min_length=1, max_length=120)
    phone: Optional[str] = Field(default=None, max_length=20)
    language: str = "en"
    village: Optional[str] = Field(default=None, max_length=120)


class AssessmentIn(BaseModel):
    id: str = Field(min_length=8, max_length=64)
    worker_id: str
    language: str = "en"
    declaration_text: str = Field(default="", max_length=6000)
    declared_years: Optional[float] = Field(default=None, ge=0, le=70)
    qp_code: Optional[str] = None
    status: str = "in_progress"
    created_at: Optional[str] = None


class ResponseIn(BaseModel):
    id: str = Field(min_length=8, max_length=64)
    criterion_id: str
    answer_text: str = Field(default="", max_length=8000)
    self_rating: Optional[int] = Field(default=None, ge=0, le=3)
    answered_at: Optional[str] = None


class PushIn(BaseModel):
    worker: WorkerIn
    assessment: AssessmentIn
    responses: List[ResponseIn] = []


class MapIn(BaseModel):
    text: str = Field(max_length=6000)
    language: str = "en"
    top_k: int = Field(default=3, ge=1, le=6)


class AssessorLogin(BaseModel):
    username: str
    password: str


class ScoreItem(BaseModel):
    criterion_id: str
    score: int = Field(ge=0, le=3)
    comment: Optional[str] = Field(default=None, max_length=1000)


class ScoresIn(BaseModel):
    scores: List[ScoreItem]
    aids_shown: bool = True


class SignOffIn(BaseModel):
    decision: str
    reasoning: str = Field(default="", max_length=2000)


# ------------------------------------------------------------------ helpers
def lang_of(v: str) -> str:
    return v if v in VALID_LANGS else "en"


def get_assessment(conn, aid: str):
    row = conn.execute("SELECT * FROM assessments WHERE id=?", (aid,)).fetchone()
    if not row:
        raise HTTPException(404, "Assessment not found")
    return row


def authorize_view(conn, aid: str, p: Principal):
    a = get_assessment(conn, aid)
    if p.role == "worker" and a["worker_id"] != p.id:
        raise HTTPException(403, "Not your assessment")
    return a


def evidence_counts(conn, aid: str) -> Dict[str, int]:
    return {r["criterion_id"]: r["c"] for r in conn.execute(
        "SELECT criterion_id, COUNT(*) c FROM evidence WHERE assessment_id=? GROUP BY criterion_id", (aid,))}


def refresh_ai(conn, aid: str, cid: str):
    ctx = catalogue.get_criterion(cid)
    r = conn.execute("SELECT answer_text, ai_json FROM responses WHERE assessment_id=? AND criterion_id=?", (aid, cid)).fetchone()
    if not ctx or not r:
        return
    ev = evidence_counts(conn, aid).get(cid, 0)
    rule = suggest.suggest(ctx["criterion"], r["answer_text"], ev)
    old = loads(r["ai_json"], {}) or {}
    sha = hashlib.sha256((r["answer_text"] or "").encode()).hexdigest()[:16]
    keep_llm = old.get("llm") if old.get("answer_sha") == sha else None
    conn.execute("UPDATE responses SET ai_json=? WHERE assessment_id=? AND criterion_id=?",
                 (json.dumps({"rule": rule, "llm": keep_llm, "answer_sha": sha}, ensure_ascii=False), aid, cid))


def ai_scores(conn, aid: str) -> Dict[str, int]:
    out = {}
    for r in conn.execute("SELECT criterion_id, ai_json FROM responses WHERE assessment_id=?", (aid,)):
        j = loads(r["ai_json"], {}) or {}
        if j.get("rule"):
            out[r["criterion_id"]] = j["rule"]["suggested_score"]
    return out


def scores_by_assessor(conn, aid: str) -> Dict[str, Dict[str, int]]:
    d: Dict[str, Dict[str, int]] = {}
    for r in conn.execute("SELECT assessor_id, criterion_id, score FROM assessor_scores WHERE assessment_id=?", (aid,)):
        d.setdefault(r["assessor_id"], {})[r["criterion_id"]] = r["score"]
    return d


def profile_for(conn, a, who: str, lang: str):
    """who: assessor id | 'consensus' | 'final'. Returns (profile, source)."""
    qp = catalogue.get(a["qp_code"]) if a["qp_code"] else None
    if not qp:
        raise HTTPException(409, "No qualification pack selected for this assessment")
    by = scores_by_assessor(conn, a["id"])
    if who == "final":
        so = conn.execute("SELECT assessor_id FROM sign_offs WHERE assessment_id=? ORDER BY created_at DESC LIMIT 1", (a["id"],)).fetchone()
        who = so["assessor_id"] if so else "consensus"
    if who != "consensus" and who in by:
        return rubric.compute_profile(qp, by[who], lang), "assessor"
    if by:
        crit_ids = {c["id"] for n in qp["nos"] for c in n["criteria"]}
        cons = {}
        for cid in crit_ids:
            vals = {k: v[cid] for k, v in by.items() if cid in v}
            s = rubric.consensus(vals)
            if s is not None:
                cons[cid] = s
        return rubric.compute_profile(qp, cons, lang), "assessor_consensus"
    return rubric.compute_profile(qp, ai_scores(conn, a["id"]), lang), "ai_provisional"


def assessment_row_summary(conn, a) -> dict:
    qp = catalogue.get(a["qp_code"]) if a["qp_code"] else None
    total = sum(len(n["criteria"]) for n in qp["nos"]) if qp else 0
    answered = conn.execute("SELECT COUNT(*) c FROM responses WHERE assessment_id=? AND TRIM(answer_text)!=''", (a["id"],)).fetchone()["c"]
    ev = conn.execute("SELECT COUNT(*) c FROM evidence WHERE assessment_id=?", (a["id"],)).fetchone()["c"]
    scorers = conn.execute("SELECT COUNT(DISTINCT assessor_id) c FROM assessor_scores WHERE assessment_id=?", (a["id"],)).fetchone()["c"]
    w = conn.execute("SELECT name, phone FROM workers WHERE id=?", (a["worker_id"],)).fetchone()
    return {"id": a["id"], "worker_id": a["worker_id"], "worker_name": w["name"] if w else "", "worker_phone": w["phone"] if w else None,
            "qp_code": a["qp_code"], "qp_title": loc(qp["title"], a["language"]) if qp else None, "status": a["status"],
            "answered": answered, "total_criteria": total, "evidence_count": ev, "assessors_scored": scorers,
            "created_at": a["created_at"], "submitted_at": a["submitted_at"], "updated_at": a["updated_at"]}


def detail(conn, a, p: Principal) -> dict:
    lang = lang_of(a["language"])
    is_assessor = p.role == "assessor"
    w = conn.execute("SELECT * FROM workers WHERE id=?", (a["worker_id"],)).fetchone()
    out = {"assessment": {k: a[k] for k in ("id", "worker_id", "language", "declaration_text", "declared_years", "qp_code",
                                              "status", "created_at", "submitted_at", "updated_at")},
           "worker": dict(w) if w else None, "match": loads(a["match_json"]),
           "checklist": catalogue.checklist(a["qp_code"], lang) if a["qp_code"] else None}
    resp = {}
    for r in conn.execute("SELECT * FROM responses WHERE assessment_id=?", (a["id"],)):
        item = {"id": r["id"], "criterion_id": r["criterion_id"], "answer_text": r["answer_text"],
                "self_rating": r["self_rating"], "answered_at": r["answered_at"]}
        if is_assessor:
            item["ai"] = loads(r["ai_json"])
        resp[r["criterion_id"]] = item
    out["responses"] = resp
    evs = []
    for e in conn.execute("SELECT * FROM evidence WHERE assessment_id=? ORDER BY created_at", (a["id"],)):
        item = {"id": e["id"], "criterion_id": e["criterion_id"], "kind": e["kind"], "mime": e["mime"], "size": e["size"],
                "captured_at": e["captured_at"], "url": f"/api/evidence/{e['id']}/file"}
        if is_assessor:
            item["ai"] = loads(e["ai_json"])
        evs.append(item)
    out["evidence"] = evs
    if is_assessor:
        by = scores_by_assessor(conn, a["id"])
        mine = conn.execute("SELECT criterion_id, score, comment, aids_shown FROM assessor_scores WHERE assessment_id=? AND assessor_id=?",
                            (a["id"], p.id)).fetchall()
        out["my_scores"] = {r["criterion_id"]: {"score": r["score"], "comment": r["comment"], "aids_shown": bool(r["aids_shown"])} for r in mine}
        names = {r["id"]: r["display_name"] for r in conn.execute("SELECT id, display_name FROM users WHERE role='assessor'")}
        out["other_assessors"] = [{"assessor": names.get(k, k), "scored": len(v)} for k, v in by.items() if k != p.id]
        so = conn.execute("SELECT s.*, u.display_name FROM sign_offs s JOIN users u ON u.id=s.assessor_id WHERE s.assessment_id=? ORDER BY s.created_at DESC",
                          (a["id"],)).fetchall()
        out["sign_offs"] = [{"assessor": r["display_name"], "decision": r["decision"], "ai_recommendation": r["ai_recommendation"],
                             "overridden": bool(r["overridden"]), "reasoning": r["reasoning"], "created_at": r["created_at"]} for r in so]
        if a["qp_code"]:
            out["profile"], out["scores_source"] = profile_for(conn, a, p.id, lang)
    else:
        so = conn.execute("SELECT decision, created_at FROM sign_offs WHERE assessment_id=? ORDER BY created_at DESC LIMIT 1", (a["id"],)).fetchone()
        if so and a["qp_code"]:
            out["result"] = {"decision": so["decision"], "signed_at": so["created_at"]}
            out["profile"], out["scores_source"] = profile_for(conn, a, "final", lang)
    return out


# ------------------------------------------------------------------ background AI
def enrich_llm(aid: str, criterion_ids: List[str]):
    if not llm.status()["available"]:
        return
    with db.session() as conn:
        a = conn.execute("SELECT language FROM assessments WHERE id=?", (aid,)).fetchone()
        if not a:
            return
        for cid in criterion_ids:
            ctx = catalogue.get_criterion(cid)
            r = conn.execute("SELECT answer_text, ai_json FROM responses WHERE assessment_id=? AND criterion_id=?", (aid, cid)).fetchone()
            if not ctx or not r:
                continue
            c = ctx["criterion"]
            res = llm.review_answer(loc(c["text"], "en"), loc(c["task"], "en"), [i["en"] for i in c.get("indicators", [])],
                                    r["answer_text"], a["language"])
            if res:
                j = loads(r["ai_json"], {}) or {}
                j["llm"] = res
                rule = j.get("rule") or {}
                j["llm_disagrees"] = abs(res["suggested_score"] - rule.get("suggested_score", res["suggested_score"])) >= 2
                conn.execute("UPDATE responses SET ai_json=? WHERE assessment_id=? AND criterion_id=?",
                             (json.dumps(j, ensure_ascii=False), aid, cid))


def analyze_evidence(eid: str):
    if not config.GEMINI_API_KEY:
        return
    with db.session() as conn:
        e = conn.execute("SELECT * FROM evidence WHERE id=?", (eid,)).fetchone()
        if not e:
            return
        ctx = catalogue.get_criterion(e["criterion_id"])
        if not ctx:
            return
        c = ctx["criterion"]
        res = llm.describe_image(config.UPLOAD_DIR / e["assessment_id"] / e["filename"], e["mime"] or "",
                                 loc(c["text"], "en"), [i["en"] for i in c.get("indicators", [])])
        if res:
            conn.execute("UPDATE evidence SET ai_json=? WHERE id=?", (json.dumps(res, ensure_ascii=False), eid))


# ------------------------------------------------------------------ system / catalogue
@app.get("/api/health")
def health():
    return {"status": "ok", "catalogue_version": catalogue.version, "packs": len(catalogue.packs),
            "criteria": len(catalogue.criteria), "time": now()}


@app.get("/api/ai/status")
def ai_status():
    s = llm.status()
    return {"mapping_engine": {"name": "tfidf_word_char_v1", "packs_indexed": len(matching.engine.codes),
                               "example_declarations": matching.engine.n_examples},
            "scoring_engine": {"name": "rubric_indicator_matcher_v1"}, "llm": s,
            "note": "LLM output is advisory only; scores and decisions are always made by the assessor."}


@app.get("/api/catalogue")
def list_catalogue(lang: str = "en"):
    return {"version": catalogue.version, "packs": catalogue.summary(lang_of(lang))}


@app.get("/api/catalogue/export")
def export_catalogue():
    """Full machine-readable catalogue so the app can map and run checklists offline."""
    return catalogue.export_full()


@app.get("/api/catalogue/{code}/checklist")
def get_checklist(code: str, lang: str = "en"):
    c = catalogue.checklist(code, lang_of(lang))
    if not c:
        raise HTTPException(404, "Unknown qualification pack")
    return c


@app.get("/api/rubric")
def get_rubric():
    return {"scale": [{"score": k, **v} for k, v in suggest.ANCHORS.items()],
            "pass_rules": {"nos_pass_mark_default_pct": int(rubric.PASS_NOS_DEFAULT * 100),
                           "critical_criterion_min_score": rubric.CRITICAL_MIN_SCORE,
                           "certify_overall_pct": int(rubric.CERTIFY_OVERALL * 100),
                           "partial_overall_pct": int(rubric.PARTIAL_OVERALL * 100)}}


# ------------------------------------------------------------------ auth
@app.post("/api/auth/worker")
def auth_worker(w: WorkerIn, conn=Depends(get_db)):
    phone = re.sub(r"[^\d+]", "", w.phone or "") or None
    t = now()
    row = conn.execute("SELECT id FROM workers WHERE id=?", (w.id,)).fetchone()
    if row:
        conn.execute("UPDATE workers SET name=?, phone=?, language=?, village=?, updated_at=? WHERE id=?",
                     (w.name.strip(), phone, lang_of(w.language), w.village, t, w.id))
    else:
        conn.execute("INSERT INTO workers(id,name,phone,language,village,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                     (w.id, w.name.strip(), phone, lang_of(w.language), w.village, t, t))
        audit(conn, w.id, "worker_registered", w.id)
    return {"token": create_token(w.id, "worker"), "role": "worker", "worker_id": w.id}


@app.post("/api/auth/assessor")
def auth_assessor(body: AssessorLogin, conn=Depends(get_db)):
    row = conn.execute("SELECT * FROM users WHERE username=? AND role='assessor'", (body.username.strip(),)).fetchone()
    if not row or not check_password(body.password, row["password_hash"] or ""):
        audit(conn, body.username, "assessor_login_failed")
        conn.commit()
        raise HTTPException(401, "Wrong username or password")
    audit(conn, row["id"], "assessor_login")
    return {"token": create_token(row["id"], "assessor"), "role": "assessor", "assessor_id": row["id"],
            "display_name": row["display_name"]}


# ------------------------------------------------------------------ mapping
@app.post("/api/map")
def map_declaration(body: MapIn, p: Principal = Depends(current_principal)):
    res = matching.engine.rank(body.text, body.top_k)
    for m in res["matches"]:
        qp = catalogue.get(m["qp_code"])
        m["pack"] = catalogue.pack_summary(qp, lang_of(body.language))
    return res


# ------------------------------------------------------------------ worker sync
@app.post("/api/sync/push")
def sync_push(body: PushIn, bg: BackgroundTasks, p: Principal = Depends(current_principal), conn=Depends(get_db)):
    if p.role != "worker" or p.id != body.worker.id or body.assessment.worker_id != p.id:
        raise HTTPException(403, "Token does not match this worker")
    t = now()
    w, a_in = body.worker, body.assessment
    phone = re.sub(r"[^\d+]", "", w.phone or "") or None
    if conn.execute("SELECT 1 FROM workers WHERE id=?", (w.id,)).fetchone():
        conn.execute("UPDATE workers SET name=?, phone=?, language=?, village=?, updated_at=? WHERE id=?",
                     (w.name.strip(), phone, lang_of(w.language), w.village, t, w.id))
    else:
        conn.execute("INSERT INTO workers(id,name,phone,language,village,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                     (w.id, w.name.strip(), phone, lang_of(w.language), w.village, t, t))
    if a_in.qp_code and not catalogue.get(a_in.qp_code):
        raise HTTPException(422, f"Unknown qualification pack {a_in.qp_code}")
    if a_in.status not in ("in_progress", "submitted"):
        raise HTTPException(422, "status must be in_progress or submitted")

    existing = conn.execute("SELECT * FROM assessments WHERE id=?", (a_in.id,)).fetchone()
    if existing and existing["worker_id"] != p.id:
        raise HTTPException(403, "Assessment belongs to another worker")
    if existing and existing["status"] in ("signed_off", "under_review"):
        return {"assessment_id": a_in.id, "status": existing["status"], "locked": True, "accepted": [], "rejected": [],
                "match": loads(existing["match_json"]), "qp_code": existing["qp_code"]}

    match = matching.engine.rank(a_in.declaration_text, 3) if a_in.declaration_text.strip() else None
    qp_code = a_in.qp_code or (existing["qp_code"] if existing else None)
    if match:
        for m in match["matches"]:
            m["pack"] = catalogue.pack_summary(catalogue.get(m["qp_code"]), lang_of(a_in.language))
    status = a_in.status
    if existing and existing["status"] in ("submitted", "needs_evidence") and status == "in_progress":
        status = existing["status"]    # never downgrade
    submitted_at = existing["submitted_at"] if existing and existing["submitted_at"] else (t if status == "submitted" else None)
    if existing:
        conn.execute("""UPDATE assessments SET language=?, declaration_text=?, declared_years=?, qp_code=?, match_json=?,
                        status=?, submitted_at=?, updated_at=? WHERE id=?""",
                     (lang_of(a_in.language), a_in.declaration_text, a_in.declared_years, qp_code,
                      json.dumps(match, ensure_ascii=False) if match else existing["match_json"], status, submitted_at, t, a_in.id))
    else:
        conn.execute("""INSERT INTO assessments(id,worker_id,language,declaration_text,declared_years,qp_code,match_json,status,
                        created_at,submitted_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                     (a_in.id, p.id, lang_of(a_in.language), a_in.declaration_text, a_in.declared_years, qp_code,
                      json.dumps(match, ensure_ascii=False) if match else None, status, a_in.created_at or t, submitted_at, t))
        audit(conn, p.id, "assessment_created", a_in.id, {"qp": qp_code})

    valid_ids = set()
    if qp_code:
        valid_ids = {c["id"] for n in catalogue.get(qp_code)["nos"] for c in n["criteria"]}
    accepted, rejected = [], []
    for r in body.responses:
        if r.criterion_id not in valid_ids:
            rejected.append(r.criterion_id)
            continue
        cur = conn.execute("SELECT id FROM responses WHERE assessment_id=? AND criterion_id=?", (a_in.id, r.criterion_id)).fetchone()
        if cur:
            conn.execute("UPDATE responses SET answer_text=?, self_rating=?, answered_at=?, updated_at=? WHERE id=?",
                         (r.answer_text, r.self_rating, r.answered_at, t, cur["id"]))
        else:
            clash = conn.execute("SELECT 1 FROM responses WHERE id=?", (r.id,)).fetchone()
            rid = r.id if not clash else str(uuid.uuid4())
            conn.execute("INSERT INTO responses(id,assessment_id,criterion_id,answer_text,self_rating,answered_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                         (rid, a_in.id, r.criterion_id, r.answer_text, r.self_rating, r.answered_at, t))
        refresh_ai(conn, a_in.id, r.criterion_id)
        accepted.append(r.criterion_id)
    if status == "submitted":
        audit(conn, p.id, "assessment_submitted", a_in.id)
    conn.commit()
    if accepted and (config.GEMINI_API_KEY or config.OLLAMA_URL):
        bg.add_task(enrich_llm, a_in.id, accepted)
    return {"assessment_id": a_in.id, "status": status, "qp_code": qp_code, "locked": False,
            "accepted": accepted, "rejected": rejected, "match": match}


@app.post("/api/evidence")
async def upload_evidence(bg: BackgroundTasks, id: str = Form(...), assessment_id: str = Form(...), criterion_id: str = Form(...),
                          kind: str = Form("photo"), captured_at: Optional[str] = Form(None), file: UploadFile = File(...),
                          p: Principal = Depends(current_principal)):
    if p.role != "worker":
        raise HTTPException(403, "Workers upload evidence")
    if kind not in ("photo", "video"):
        raise HTTPException(422, "kind must be photo or video")
    if not re.fullmatch(r"[A-Za-z0-9\-]{8,64}", id):
        raise HTTPException(422, "Invalid evidence id")
    mime = (file.content_type or "").lower()
    if not mime or mime == "application/octet-stream":      # mobile clients often omit the real type
        mime = (mimetypes.guess_type(file.filename or "")[0] or "").lower()
    if not mime.startswith(config.ALLOWED_UPLOAD_PREFIXES):
        raise HTTPException(415, "Only image or video files are accepted")
    with db.session() as conn:
        a = get_assessment(conn, assessment_id)
        if a["worker_id"] != p.id:
            raise HTTPException(403, "Not your assessment")
        if a["status"] == "signed_off":
            raise HTTPException(409, "Assessment already signed off")
        ctx = catalogue.get_criterion(criterion_id)
        if not ctx or ctx["qp"]["code"] != a["qp_code"]:
            raise HTTPException(422, "Criterion does not belong to this assessment's qualification pack")
        existing = conn.execute("SELECT * FROM evidence WHERE id=?", (id,)).fetchone()
        if existing:
            return {"id": id, "duplicate": True, "sha256": existing["sha256"]}
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_EXT:
        ext = (mimetypes.guess_extension(mime) or ".bin").replace(".jpe", ".jpg")
        if ext not in ALLOWED_EXT:
            ext = ".jpg" if mime.startswith("image/") else ".mp4"
    folder = config.UPLOAD_DIR / assessment_id
    folder.mkdir(parents=True, exist_ok=True)
    fname = f"{id}{ext}"
    h, size = hashlib.sha256(), 0
    try:
        with open(folder / fname, "wb") as out:
            while True:
                chunk = await file.read(1024 * 256)
                if not chunk:
                    break
                size += len(chunk)
                if size > config.MAX_UPLOAD_BYTES:
                    raise HTTPException(413, f"File larger than {config.MAX_UPLOAD_BYTES // (1024 * 1024)} MB")
                h.update(chunk)
                out.write(chunk)
    except HTTPException:
        (folder / fname).unlink(missing_ok=True)
        raise
    if size == 0:
        (folder / fname).unlink(missing_ok=True)
        raise HTTPException(422, "Empty file")
    with db.session() as conn:
        conn.execute("""INSERT INTO evidence(id,assessment_id,criterion_id,kind,filename,mime,sha256,size,captured_at,created_at)
                        VALUES (?,?,?,?,?,?,?,?,?,?)""",
                     (id, assessment_id, criterion_id, kind, fname, mime, h.hexdigest(), size, captured_at, now()))
        audit(conn, p.id, "evidence_uploaded", assessment_id, {"criterion": criterion_id, "sha256": h.hexdigest()})
        refresh_ai(conn, assessment_id, criterion_id)
    bg.add_task(analyze_evidence, id)
    return {"id": id, "duplicate": False, "sha256": h.hexdigest(), "size": size}


@app.get("/api/worker/assessments")
def worker_assessments(p: Principal = Depends(current_principal), conn=Depends(get_db)):
    if p.role != "worker":
        raise HTTPException(403, "Workers only")
    rows = conn.execute("SELECT * FROM assessments WHERE worker_id=? ORDER BY created_at DESC", (p.id,)).fetchall()
    return [assessment_row_summary(conn, a) for a in rows]


@app.get("/api/assessments/{aid}")
def get_assessment_detail(aid: str, p: Principal = Depends(current_principal), conn=Depends(get_db)):
    return detail(conn, authorize_view(conn, aid, p), p)


@app.get("/api/evidence/{eid}/file")
def evidence_file(eid: str, token: Optional[str] = Query(default=None), authorization: Optional[str] = Header(default=None),
                  conn=Depends(get_db)):
    raw = token
    if not raw and authorization and authorization.lower().startswith("bearer "):
        raw = authorization.split(" ", 1)[1].strip()
    data = verify_token(raw) if raw else None
    if not data:
        raise HTTPException(401, "Valid token required")
    e = conn.execute("SELECT * FROM evidence WHERE id=?", (eid,)).fetchone()
    if not e:
        raise HTTPException(404, "Not found")
    if data["role"] == "worker":
        a = conn.execute("SELECT worker_id FROM assessments WHERE id=?", (e["assessment_id"],)).fetchone()
        if not a or a["worker_id"] != data["sub"]:
            raise HTTPException(403, "Forbidden")
    path = config.UPLOAD_DIR / e["assessment_id"] / e["filename"]
    if not path.exists():
        raise HTTPException(404, "File missing")
    return FileResponse(path, media_type=e["mime"] or "application/octet-stream")


# ------------------------------------------------------------------ assessor
@app.get("/api/assessor/queue")
def assessor_queue(status: Optional[str] = None, p: Principal = Depends(require_assessor), conn=Depends(get_db)):
    q = "SELECT * FROM assessments WHERE status != 'in_progress'"
    args: list = []
    if status:
        q += " AND status=?"
        args.append(status)
    q += " ORDER BY COALESCE(submitted_at, created_at) DESC LIMIT 200"
    out = []
    for a in conn.execute(q, args).fetchall():
        s = assessment_row_summary(conn, a)
        s["scored_by_me"] = conn.execute("SELECT COUNT(*) c FROM assessor_scores WHERE assessment_id=? AND assessor_id=?",
                                         (a["id"], p.id)).fetchone()["c"]
        out.append(s)
    return out


@app.put("/api/assessor/assessments/{aid}/scores")
def put_scores(aid: str, body: ScoresIn, p: Principal = Depends(require_assessor), conn=Depends(get_db)):
    a = get_assessment(conn, aid)
    if a["status"] == "in_progress":
        raise HTTPException(409, "Worker has not submitted this assessment yet")
    if not a["qp_code"]:
        raise HTTPException(409, "No qualification pack selected")
    if conn.execute("SELECT 1 FROM sign_offs WHERE assessment_id=? AND assessor_id=?", (aid, p.id)).fetchone():
        raise HTTPException(409, "You have already signed off this assessment")
    valid = {c["id"] for n in catalogue.get(a["qp_code"])["nos"] for c in n["criteria"]}
    bad = [s.criterion_id for s in body.scores if s.criterion_id not in valid]
    if bad:
        raise HTTPException(422, f"Criteria not in this pack: {bad}")
    t = now()
    for s in body.scores:
        conn.execute("""INSERT INTO assessor_scores(assessment_id,criterion_id,assessor_id,score,comment,aids_shown,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?,?)
                        ON CONFLICT(assessment_id,criterion_id,assessor_id)
                        DO UPDATE SET score=excluded.score, comment=excluded.comment, aids_shown=excluded.aids_shown, updated_at=excluded.updated_at""",
                     (aid, s.criterion_id, p.id, s.score, s.comment, 1 if body.aids_shown else 0, t, t))
    if a["status"] == "submitted":
        conn.execute("UPDATE assessments SET status='under_review', updated_at=? WHERE id=?", (t, aid))
    audit(conn, p.id, "scores_saved", aid, {"n": len(body.scores), "aids_shown": body.aids_shown})
    a = get_assessment(conn, aid)
    prof, src = profile_for(conn, a, p.id, lang_of(a["language"]))
    return {"profile": prof, "scores_source": src, "status": a["status"]}


@app.post("/api/assessor/assessments/{aid}/sign-off")
def sign_off(aid: str, body: SignOffIn, p: Principal = Depends(require_assessor), conn=Depends(get_db)):
    if body.decision not in DECISIONS:
        raise HTTPException(422, f"decision must be one of {sorted(DECISIONS)}")
    a = get_assessment(conn, aid)
    if a["status"] == "in_progress":
        raise HTTPException(409, "Worker has not submitted this assessment yet")
    mine = scores_by_assessor(conn, aid).get(p.id, {})
    prof, _ = profile_for(conn, a, p.id, lang_of(a["language"])) if mine else (None, None)
    if body.decision != "more_evidence":
        if not prof or not prof["complete"]:
            raise HTTPException(409, "Score every criterion before signing off")
    rec_code = prof["recommendation"]["code"] if prof else "incomplete"
    expected = REC_TO_DECISION.get(rec_code)
    overridden = body.decision != "more_evidence" and expected is not None and body.decision != expected
    if (overridden or body.decision == "more_evidence") and len(body.reasoning.strip()) < 10:
        raise HTTPException(422, "Reasoning (at least 10 characters) is required when overriding the system recommendation or requesting more evidence")
    t = now()
    if body.decision == "more_evidence":
        new_status = "needs_evidence"
    else:
        new_status = "signed_off"
        conn.execute("""INSERT INTO sign_offs(assessment_id,assessor_id,decision,ai_recommendation,overridden,reasoning,created_at)
                        VALUES (?,?,?,?,?,?,?)
                        ON CONFLICT(assessment_id,assessor_id) DO UPDATE SET decision=excluded.decision,
                        ai_recommendation=excluded.ai_recommendation, overridden=excluded.overridden,
                        reasoning=excluded.reasoning, created_at=excluded.created_at""",
                     (aid, p.id, body.decision, rec_code, 1 if overridden else 0, body.reasoning.strip(), t))
    conn.execute("UPDATE assessments SET status=?, updated_at=? WHERE id=?", (new_status, t, aid))
    audit(conn, p.id, "sign_off", aid, {"decision": body.decision, "system_recommendation": rec_code, "overridden": overridden,
                                        "reasoning": body.reasoning.strip()})
    return {"status": new_status, "decision": body.decision, "system_recommendation": rec_code, "overridden": overridden}


# ------------------------------------------------------------------ profile / report / analytics
def _report_payload(conn, a, p: Principal) -> dict:
    lang = "en"
    who = p.id if p.role == "assessor" else "final"
    prof, src = profile_for(conn, a, who, lang)
    w = conn.execute("SELECT * FROM workers WHERE id=?", (a["worker_id"],)).fetchone()
    so = conn.execute("SELECT s.*, u.display_name FROM sign_offs s JOIN users u ON u.id=s.assessor_id WHERE s.assessment_id=? "
                      "ORDER BY s.created_at DESC LIMIT 1", (a["id"],)).fetchone()
    return {"worker": dict(w) if w else {}, "assessment": dict(a), "profile": prof, "scores_source": src,
            "ai_scores": ai_scores(conn, a["id"]),
            "sign_off": None if not so else {"decision": so["decision"], "assessor": so["display_name"], "overridden": bool(so["overridden"]),
                                             "reasoning": so["reasoning"], "created_at": so["created_at"]}}


@app.get("/api/assessments/{aid}/profile")
def get_profile(aid: str, lang: str = "en", p: Principal = Depends(current_principal), conn=Depends(get_db)):
    a = authorize_view(conn, aid, p)
    if p.role == "worker" and a["status"] != "signed_off":
        raise HTTPException(403, "Profile is available after assessor sign-off")
    prof, src = profile_for(conn, a, p.id if p.role == "assessor" else "final", lang_of(lang))
    return {"profile": prof, "scores_source": src}


@app.get("/api/assessments/{aid}/report.pdf")
def get_report(aid: str, p: Principal = Depends(current_principal), conn=Depends(get_db)):
    a = authorize_view(conn, aid, p)
    if p.role == "worker" and a["status"] != "signed_off":
        raise HTTPException(403, "Report is available after assessor sign-off")
    pdf = build_pdf(_report_payload(conn, a, p))
    return Response(pdf, media_type="application/pdf",
                    headers={"Content-Disposition": f'attachment; filename="rpl_report_{aid[:8]}.pdf"'})


@app.get("/api/analytics/agreement")
def analytics_agreement(p: Principal = Depends(require_assessor), conn=Depends(get_db)):
    rows = [dict(r) for r in conn.execute("SELECT assessment_id, criterion_id, assessor_id, score, aids_shown FROM assessor_scores")]
    ai = []
    for r in conn.execute("SELECT assessment_id, criterion_id, ai_json FROM responses WHERE ai_json IS NOT NULL"):
        j = loads(r["ai_json"], {}) or {}
        ai.append({"assessment_id": r["assessment_id"], "criterion_id": r["criterion_id"],
                   "ai_score": (j.get("rule") or {}).get("suggested_score")})
    rep = agreement_report(rows, ai)
    rep["total_scores"] = len(rows)
    return rep
