import logging
from fastapi import FastAPI
from app.config import settings
from app.core.logging_config import setup_logging
from app.api.health import router as health_router

setup_logging(settings.LOG_LEVEL)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Guitar Tuner AI Backend",
    version="0.1.0",
)

app.include_router(health_router, prefix="/api")

logger.info("[main] 🎸 Guitar Tuner AI Backend pornit — ENV=%s", settings.ENV)


@app.get("/")
def root() -> dict[str, str]:
    """Endpoint rădăcină cu link către documentație."""
    return {"message": "Guitar Tuner AI Backend — vezi /docs"}
