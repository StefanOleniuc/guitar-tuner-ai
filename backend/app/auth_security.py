"""Securitate autentificare: hash de parole (bcrypt) + token-uri JWT."""

import os
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

# Secretul JWT — în producție se setează prin variabila de mediu.
# Valoarea default e DOAR pentru dezvoltare locală.
_SECRET: str = os.environ.get("GTUNE_JWT_SECRET", "gtune-dev-secret-change-me")
_ALGORITHM = "HS256"
_TOKEN_DAYS = 30


def hash_password(password: str) -> str:
    """Hash bcrypt al parolei (salt inclus)."""
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    """Verifică parola față de hash-ul stocat."""
    try:
        return bcrypt.checkpw(password.encode("utf-8"), hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def create_token(user_id: int) -> str:
    """Generează un JWT semnat pentru utilizator (valabil _TOKEN_DAYS zile)."""
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(days=_TOKEN_DAYS),
    }
    return jwt.encode(payload, _SECRET, algorithm=_ALGORITHM)


def decode_token(token: str) -> int | None:
    """Validează un JWT și întoarce id-ul utilizatorului, sau None."""
    try:
        payload = jwt.decode(token, _SECRET, algorithms=[_ALGORITHM])
        return int(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        return None
