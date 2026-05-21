import logging

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/pitch", tags=["pitch"])

# Limită prudentă: 1.5 s @ 16 kHz PCM16 = ~48 KB. 200 KB lasă o margine
# generoasă fără să permită upload-uri abuzive.
MAX_UPLOAD_BYTES: int = 200 * 1024


class PitchDetectionResponse(BaseModel):
    """Răspuns CREPE: frecvența fundamentală + încredere + durata analizată."""

    frequency: float = Field(..., description="Frecvența detectată în Hz")
    confidence: float = Field(..., ge=0.0, le=1.0, description="Încrederea modelului (0..1)")
    duration_ms: int = Field(..., ge=0, description="Durata semnalului analizat (ms)")


@router.post("/detect", response_model=PitchDetectionResponse)
async def detect_pitch(
    request: Request,
    audio: UploadFile = File(..., description="Audio PCM16 mono raw (recomandat 16 kHz, ~1.5 s)"),
) -> PitchDetectionResponse:
    """Estimare AI a frecvenței fundamentale dintr-un sample PCM16.

    Verificare punctuală (NU real-time): clientul mobil capturează ~1.5 s
    de audio și îl trimite aici pentru o măsurătoare de precizie.
    """
    logger.info("[pitch] Cerere /detect primită (content_type=%s)", audio.content_type)

    raw = await audio.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Fișier audio gol")
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=400,
            detail=f"Audio prea mare: {len(raw)} bytes (max {MAX_UPLOAD_BYTES})",
        )

    crepe_service = getattr(request.app.state, "crepe_service", None)
    if crepe_service is None:
        logger.error("❌ [pitch] CrepeService nu e disponibil în app.state")
        raise HTTPException(status_code=500, detail="Serviciu AI indisponibil")

    try:
        result = crepe_service.predict(raw)
    except ValueError as e:
        logger.warning("🔶 [pitch] Audio invalid: %s", e)
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        logger.error("❌ [pitch] Eroare internă la predicție", exc_info=True)
        raise HTTPException(status_code=500, detail="Eroare internă la detecție") from e

    return PitchDetectionResponse(**result)
