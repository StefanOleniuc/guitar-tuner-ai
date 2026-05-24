"""Punct de intrare al backend-ului Guitar Tuner AI.

Arhitectură:
  • FastAPI ca framework web (rute REST + documentație auto la /docs)
  • CREPE (TensorFlow) pentru detecția frecvenței — model AI încărcat la startup
  • PostgreSQL pentru persistența conturilor / preferințelor / istoricului
  • SendGrid HTTPS API pentru emailuri de resetare parolă
  • JWT (HS256) pentru sesiuni de autentificare (vezi auth_security)

Rute:
  /api/health             — health check
  /api/pitch/detect       — POST audio PCM16 → frecvență + confidence (AI)
  /api/auth/{register,login,me,reset-password,reset-confirm}
  /api/user/{preferences,tuning-sessions}

Deployment:
  Docker (vezi Dockerfile) → Railway (vezi railway.toml).
"""

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI

from app import auth_db
from app.api.auth import router as auth_router
from app.api.health import router as health_router
from app.api.pitch import router as pitch_router
from app.api.user import router as user_router
from app.config import settings
from app.core.logging_config import setup_logging
from app.services.crepe_service import CrepeService

setup_logging(settings.LOG_LEVEL)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Hook de startup/shutdown FastAPI.

    La pornire:
      1. Creează schema PostgreSQL dacă nu există (idempotent).
      2. Instanțiază CrepeService — încarcă modelul AI în memorie
         (~2-3 secunde) ca să primul request să NU plătească latency-ul.
      3. Stochează serviciul în `app.state` pentru a fi accesat din rute.
    """
    logger.info("[main] Inițializare bază de date conturi...")
    auth_db.init_db()
    logger.info("[main] Inițializare CrepeService...")
    app.state.crepe_service = CrepeService()
    logger.info(
        "[main] 🎸 Guitar Tuner AI Backend pornit — ENV=%s, AI + Auth ready",
        settings.ENV,
    )
    yield
    logger.info("[main] Oprire backend")


app = FastAPI(
    title="Guitar Tuner AI Backend",
    version="0.2.0",
    lifespan=lifespan,
)

app.include_router(health_router, prefix="/api")
app.include_router(pitch_router)
app.include_router(auth_router)
app.include_router(user_router)


@app.get("/")
def root() -> dict[str, str]:
    """Endpoint rădăcină cu link către documentație."""
    return {"message": "Guitar Tuner AI Backend — vezi /docs"}
