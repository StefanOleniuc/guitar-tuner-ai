"""Dependențe FastAPI partajate (auth Bearer)."""

from fastapi import Header, HTTPException

from app import auth_db
from app.auth_security import decode_token


def require_user(authorization: str | None = Header(default=None)) -> dict:
    """Validează header-ul `Authorization: Bearer <jwt>` și întoarce userul.

    Folosit cu `Depends(require_user)` pe rutele protejate.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Token de autentificare lipsă")
    user_id = decode_token(authorization[7:])
    if user_id is None:
        raise HTTPException(status_code=401, detail="Sesiune invalidă sau expirată")
    row = auth_db.get_user_by_id(user_id)
    if row is None:
        raise HTTPException(status_code=401, detail="Cont inexistent")
    return row
