import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI

from app.api.health import router as health_router
from app.api.pitch import router as pitch_router
from app.config import settings
from app.core.logging_config import setup_logging
from app.services.crepe_service import CrepeService

setup_logging(settings.LOG_LEVEL)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Inițializează resursele scumpe la pornire (modelul CREPE) și le
    expune prin app.state. Modelul rămâne în memorie pe toată durata
    procesului — fără reload per cerere.
    """
    logger.info("[main] Inițializare CrepeService...")
    app.state.crepe_service = CrepeService()
    logger.info(
        "[main] 🎸 Guitar Tuner AI Backend pornit — ENV=%s, AI ready",
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


@app.get("/")
def root() -> dict[str, str]:
    """Endpoint rădăcină cu link către documentație."""
    return {"message": "Guitar Tuner AI Backend — vezi /docs"}
