"""Runtime configuration (environment driven, no hardcoded secrets)."""
import os
import secrets
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.getenv("KS_DATA_DIR", BASE_DIR / "data"))
STORAGE_DIR = Path(os.getenv("KS_STORAGE_DIR", BASE_DIR / "storage"))
DB_PATH = Path(os.getenv("KS_DB_PATH", STORAGE_DIR / "kaushalsetu.db"))
UPLOAD_DIR = Path(os.getenv("KS_UPLOAD_DIR", STORAGE_DIR / "uploads"))
CATALOGUE_DIR = DATA_DIR / "qualification_packs"
EXAMPLES_DIR = DATA_DIR / "examples"

MAX_UPLOAD_BYTES = int(os.getenv("KS_MAX_UPLOAD_MB", "25")) * 1024 * 1024
ALLOWED_UPLOAD_PREFIXES = ("image/", "video/")

TOKEN_TTL_SECONDS = int(os.getenv("KS_TOKEN_TTL_HOURS", "72")) * 3600

# Optional AI providers. Core mapping/scoring never needs them.
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
OLLAMA_URL = os.getenv("OLLAMA_URL", "").strip().rstrip("/")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3.2:3b")
LLM_TIMEOUT = float(os.getenv("KS_LLM_TIMEOUT", "20"))


def get_secret() -> bytes:
    """Signing secret: env var, else a random one persisted in storage."""
    env = os.getenv("KS_SECRET", "").strip()
    if env:
        return env.encode()
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)
    f = STORAGE_DIR / ".secret"
    if not f.exists():
        f.write_text(secrets.token_hex(32))
    return f.read_text().strip().encode()
