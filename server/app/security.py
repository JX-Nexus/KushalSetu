"""Signed bearer tokens + password hashing (stdlib only)."""
import base64
import hashlib
import hmac
import json
import os
import time
from typing import Optional

from fastapi import Depends, Header, HTTPException

from . import config
from .db import get_db

_SECRET = None


def _secret() -> bytes:
    global _SECRET
    if _SECRET is None:
        _SECRET = config.get_secret()
    return _SECRET


def _b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def create_token(sub: str, role: str, ttl: Optional[int] = None) -> str:
    body = _b64(json.dumps({"sub": sub, "role": role, "exp": int(time.time()) + (ttl or config.TOKEN_TTL_SECONDS)}).encode())
    sig = _b64(hmac.new(_secret(), body.encode(), hashlib.sha256).digest())
    return f"{body}.{sig}"


def verify_token(token: str) -> Optional[dict]:
    try:
        body, sig = token.split(".", 1)
        good = _b64(hmac.new(_secret(), body.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, good):
            return None
        data = json.loads(_unb64(body))
        if data.get("exp", 0) < time.time():
            return None
        return data
    except Exception:
        return None


def hash_password(pw: str, iters: int = 200_000) -> str:
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, iters)
    return f"pbkdf2${iters}${_b64(salt)}${_b64(dk)}"


def check_password(pw: str, stored: str) -> bool:
    try:
        _, iters, salt, dk = stored.split("$")
        calc = hashlib.pbkdf2_hmac("sha256", pw.encode(), _unb64(salt), int(iters))
        return hmac.compare_digest(calc, _unb64(dk))
    except Exception:
        return False


class Principal(dict):
    @property
    def id(self): return self["sub"]
    @property
    def role(self): return self["role"]


def current_principal(authorization: Optional[str] = Header(default=None)) -> Principal:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Missing bearer token")
    data = verify_token(authorization.split(" ", 1)[1].strip())
    if not data:
        raise HTTPException(401, "Invalid or expired token")
    return Principal(data)


def require_assessor(p: Principal = Depends(current_principal)) -> Principal:
    if p.role != "assessor":
        raise HTTPException(403, "Assessor access only")
    return p
