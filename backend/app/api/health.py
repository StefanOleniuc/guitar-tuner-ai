import logging
from fastapi import APIRouter
from app.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/health")
def health_check() -> dict[str, str]:
    """Returnează statusul aplicației."""
    logger.info("[health] Cerere health check primită")
    return {
        "status": "ok",
        "version": "0.1.0",
        "environment": settings.ENV,
    }
