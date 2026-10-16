"""SQLite persistence. Plain sqlite3 so there is nothing exotic to break."""
import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

from . import config

SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY, role TEXT NOT NULL, username TEXT UNIQUE,
  password_hash TEXT, display_name TEXT, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS workers (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, language TEXT DEFAULT 'en',
  village TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_workers_phone ON workers(phone);
CREATE TABLE IF NOT EXISTS assessments (
  id TEXT PRIMARY KEY, worker_id TEXT NOT NULL REFERENCES workers(id),
  language TEXT DEFAULT 'en', declaration_text TEXT NOT NULL DEFAULT '',
  declared_years REAL, qp_code TEXT, match_json TEXT,
  status TEXT NOT NULL DEFAULT 'in_progress',
  created_at TEXT NOT NULL, submitted_at TEXT, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS responses (
  id TEXT PRIMARY KEY, assessment_id TEXT NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,
  criterion_id TEXT NOT NULL, answer_text TEXT NOT NULL DEFAULT '', self_rating INTEGER,
  answered_at TEXT, ai_json TEXT, updated_at TEXT NOT NULL,
  UNIQUE(assessment_id, criterion_id)
);
CREATE TABLE IF NOT EXISTS evidence (
  id TEXT PRIMARY KEY, assessment_id TEXT NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,
  criterion_id TEXT NOT NULL, kind TEXT NOT NULL, filename TEXT NOT NULL,
  mime TEXT, sha256 TEXT, size INTEGER, captured_at TEXT, ai_json TEXT, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS assessor_scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  assessment_id TEXT NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,
  criterion_id TEXT NOT NULL, assessor_id TEXT NOT NULL REFERENCES users(id),
  score INTEGER NOT NULL CHECK(score BETWEEN 0 AND 3), comment TEXT,
  aids_shown INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE(assessment_id, criterion_id, assessor_id)
);
CREATE TABLE IF NOT EXISTS sign_offs (
  assessment_id TEXT NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,
  assessor_id TEXT NOT NULL REFERENCES users(id),
  decision TEXT NOT NULL, ai_recommendation TEXT, overridden INTEGER NOT NULL DEFAULT 0,
  reasoning TEXT, created_at TEXT NOT NULL,
  PRIMARY KEY (assessment_id, assessor_id)
);
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL, actor TEXT, action TEXT NOT NULL,
  target TEXT, detail TEXT
);
"""


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def connect() -> sqlite3.Connection:
    config.DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(config.DB_PATH), timeout=30, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def init_db() -> None:
    conn = connect()
    try:
        conn.executescript(SCHEMA)
        conn.commit()
    finally:
        conn.close()


def get_db():
    """FastAPI dependency: one connection per request, committed on success."""
    conn = connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@contextmanager
def session():
    conn = connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def audit(conn, actor: str, action: str, target: str = "", detail=None) -> None:
    conn.execute(
        "INSERT INTO audit_log(ts, actor, action, target, detail) VALUES (?,?,?,?,?)",
        (now(), actor, action, target, json.dumps(detail, ensure_ascii=False) if detail is not None else None),
    )


def loads(s, default=None):
    if not s:
        return default
    try:
        return json.loads(s)
    except Exception:
        return default
