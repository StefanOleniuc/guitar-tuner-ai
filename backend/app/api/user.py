"""Rute „contul meu": preferințe (instrument + A4) + istoric acordaje.

Toate endpoint-urile necesită autentificare cu Bearer JWT.
"""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app import auth_db
from app.dependencies import require_user

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/user", tags=["user"])

# Valori implicite când userul n-a salvat încă preferințe.
_DEFAULT_INSTRUMENT = "guitar"
_DEFAULT_A4 = 440.0


# Modele
class PreferencesIn(BaseModel):
    instrument: str = Field(..., min_length=1, max_length=32)
    a4: float = Field(..., ge=415.0, le=466.0)
    left_handed: bool = Field(False, alias="leftHanded")


class PreferencesOut(BaseModel):
    instrument: str
    a4: float
    left_handed: bool = Field(False, alias="leftHanded")
    updated_at: str | None

    model_config = {"populate_by_name": True}


class TuningSessionIn(BaseModel):
    instrument: str = Field(..., min_length=1, max_length=32)
    tuning_name: str = Field(..., min_length=1, max_length=64)
    strings_tuned: int = Field(..., ge=0, le=20)
    total_strings: int = Field(..., ge=1, le=20)
    duration_seconds: float = Field(..., ge=0, le=3600)
    a4: float = Field(440.0, ge=415.0, le=466.0)


class TuningSessionOut(BaseModel):
    id: int
    instrument: str
    tuning_name: str
    strings_tuned: int
    total_strings: int
    duration_seconds: float
    a4: float
    created_at: str


class TuningHistoryOut(BaseModel):
    total: int
    sessions: list[TuningSessionOut]


# Preferințe
@router.get("/preferences", response_model=PreferencesOut)
def get_preferences(
    user: Annotated[dict, Depends(require_user)],
) -> PreferencesOut:
    """Întoarce preferințele utilizatorului (sau implicit dacă lipsesc)."""
    prefs = auth_db.get_preferences(user["id"])
    if prefs is None:
        return PreferencesOut(
            instrument=_DEFAULT_INSTRUMENT,
            a4=_DEFAULT_A4,
            left_handed=False,
            updated_at=None,
        )
    return PreferencesOut(**prefs)


@router.put("/preferences", response_model=PreferencesOut)
def put_preferences(
    body: PreferencesIn,
    user: Annotated[dict, Depends(require_user)],
) -> PreferencesOut:
    """Salvează / actualizează preferințele (upsert)."""
    auth_db.set_preferences(
        user["id"], body.instrument, body.a4, body.left_handed,
    )
    saved = auth_db.get_preferences(user["id"])
    assert saved is not None
    logger.info(
        "[user] Preferințe actualizate user_id=%d → %s @ A4=%.1f%s",
        user["id"], body.instrument, body.a4,
        " (stângaci)" if body.left_handed else "",
    )
    return PreferencesOut(**saved)


# Istoric acordaje
@router.post("/tuning-sessions", response_model=TuningSessionOut)
def add_session(
    body: TuningSessionIn,
    user: Annotated[dict, Depends(require_user)],
) -> TuningSessionOut:
    """Înregistrează o sesiune de acordaj încheiată."""
    if body.strings_tuned > body.total_strings:
        # Defensive guard — nu salvăm date inconsistente.
        body.strings_tuned = body.total_strings
    session_id = auth_db.add_tuning_session(
        user_id=user["id"],
        instrument=body.instrument,
        tuning_name=body.tuning_name,
        strings_tuned=body.strings_tuned,
        total_strings=body.total_strings,
        duration_seconds=body.duration_seconds,
        a4=body.a4,
    )
    sessions = auth_db.list_tuning_sessions(user["id"], limit=1)
    assert sessions, "Sesiunea tocmai inserată trebuie să existe"
    logger.info(
        "[user] Sesiune nouă (#%d) pentru user_id=%d: %s/%s",
        session_id, user["id"], body.instrument, body.tuning_name,
    )
    return TuningSessionOut(**sessions[0])


@router.get("/tuning-sessions", response_model=TuningHistoryOut)
def list_sessions(
    user: Annotated[dict, Depends(require_user)],
    limit: int = Query(default=20, ge=1, le=100),
) -> TuningHistoryOut:
    """Cele mai recente sesiuni + numărul total."""
    sessions = auth_db.list_tuning_sessions(user["id"], limit=limit)
    total = auth_db.count_tuning_sessions(user["id"])
    return TuningHistoryOut(
        total=total,
        sessions=[TuningSessionOut(**s) for s in sessions],
    )
