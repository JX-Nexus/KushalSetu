import os
import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
_tmp = tempfile.mkdtemp(prefix="ks_test_")
os.environ["KS_STORAGE_DIR"] = _tmp
os.environ["KS_DB_PATH"] = os.path.join(_tmp, "t.db")
os.environ["KS_UPLOAD_DIR"] = os.path.join(_tmp, "uploads")
os.environ["KS_SECRET"] = "test-secret"
os.environ["KS_ASSESSORS"] = "a1:pw1:Assessor One,a2:pw2:Assessor Two"
os.environ.pop("GEMINI_API_KEY", None)
os.environ.pop("OLLAMA_URL", None)


@pytest.fixture(scope="session")
def client():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        yield c
