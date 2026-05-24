"""Wrapper pentru modelul CREPE (Convolutional Representation for Pitch Estimation).

CREPE este un CNN pre-antrenat (Kim et al., 2018) care estimă frecvența
fundamentală într-un semnal audio cu precizie sub 1 cent. Folosim varianta
"medium" — echilibru între acuratețe și timp de inferență pe CPU.

Input așteptat: audio PCM16 mono la 16 kHz, ~1.5 secunde.
Output: frecvența în Hz + confidence (0..1) + durată analizată.
"""

import logging
import time

import crepe 
import numpy as np  

logger = logging.getLogger(__name__)


class CrepeService:
    """Wrapper CREPE: PCM16 → frecvență + confidence. Model 'medium', încărcat la startup."""

    MODEL_CAPACITY: str = "medium"
    DEFAULT_SAMPLE_RATE: int = 16000
    MIN_SAMPLES: int = 1024  # minim necesar pentru analiză CREPE

    def __init__(self) -> None:
        logger.info("[crepe_service] Încărcare model CREPE (%s)...", self.MODEL_CAPACITY)
        t0 = time.perf_counter()
        # Forțăm lazy-loading la startup (nu la primul request).
        crepe.core.build_and_load_model(self.MODEL_CAPACITY)
        elapsed = time.perf_counter() - t0
        logger.info("🚀 [crepe_service] Model loaded in %.2fs", elapsed)

    def predict(
        self,
        pcm16_bytes: bytes,
        sample_rate: int = DEFAULT_SAMPLE_RATE,
    ) -> dict[str, float | int]:
        """Estimează frecvența dintr-un buffer PCM16 mono.

        Returnează frecvența cadrului cu cea mai mare încredere (CREPE produce
        o predicție la fiecare 10ms; alegem argmax(confidence)).
        """
        try:
            audio_int16 = np.frombuffer(pcm16_bytes, dtype=np.int16)
            if audio_int16.size < self.MIN_SAMPLES:
                raise ValueError(
                    f"Semnal prea scurt: {audio_int16.size} sample-uri "
                    f"(minim {self.MIN_SAMPLES})"
                )

            # PCM16 signed [-32768, 32767] → float32 [-1.0, 1.0]
            audio = audio_int16.astype(np.float32) / 32768.0

            # viterbi=False: argmax pe confidence e suficient și ~2x mai rapid.
            _time, frequency, confidence, _activation = crepe.predict(
                audio,
                sr=sample_rate,
                model_capacity=self.MODEL_CAPACITY,
                viterbi=False,
                verbose=0,
            )

            # Cadrul cu cea mai mare încredere → frecvența reprezentativă.
            best_idx = int(np.argmax(confidence))
            best_freq = float(frequency[best_idx])
            best_conf = float(confidence[best_idx])
            duration_ms = int(audio.size / sample_rate * 1000)

            logger.debug(
                "🎸 [crepe_service] freq=%.2f Hz conf=%.3f duration=%dms",
                best_freq,
                best_conf,
                duration_ms,
            )

            return {
                "frequency": best_freq,
                "confidence": best_conf,
                "duration_ms": duration_ms,
            }
        except ValueError:
            raise
        except Exception:
            logger.error(
                "❌ [crepe_service] Eroare la predicție",
                exc_info=True,
            )
            raise
