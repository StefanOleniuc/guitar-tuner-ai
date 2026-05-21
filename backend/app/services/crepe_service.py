import logging
import time

import crepe
import numpy as np

logger = logging.getLogger(__name__)


class CrepeService:
    """Wrapper peste modelul CREPE de pitch detection.

    Modelul (capacity='medium') se încarcă o singură dată la pornirea
    aplicației și este reutilizat la fiecare cerere. Detecția se face
    pe semnale PCM16 mono — convertite intern în float32 normalizat.
    """

    MODEL_CAPACITY: str = "medium"
    DEFAULT_SAMPLE_RATE: int = 16000
    MIN_SAMPLES: int = 1024  # minim necesar pentru analiză CREPE

    def __init__(self) -> None:
        logger.info("[crepe_service] Încărcare model CREPE (%s)...", self.MODEL_CAPACITY)
        t0 = time.perf_counter()
        # Forțăm încărcarea în memorie a graph-ului CNN (la primul apel
        # crepe.predict ar fi lazy-loaded; preferăm aici la startup)
        crepe.core.build_and_load_model(self.MODEL_CAPACITY)
        elapsed = time.perf_counter() - t0
        logger.info("🚀 [crepe_service] Model loaded in %.2fs", elapsed)

    def predict(
        self,
        pcm16_bytes: bytes,
        sample_rate: int = DEFAULT_SAMPLE_RATE,
    ) -> dict[str, float | int]:
        """Estimează frecvența fundamentală dintr-un buffer PCM16 mono.

        Returnează un dict cu cea mai sigură frecvență detectată din
        secvență (CREPE produce o predicție la fiecare 10 ms; alegem
        cadrul cu cea mai mare încredere).
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

            # viterbi=False: alegem oricum frame-ul cu confidence maxim
            # din secvență (nu ne interesează traiectoria netedă inter-frame),
            # iar fără HMM viterbi inferența e ~2x mai rapidă — critic
            # pentru modul AI Precision continuu (request la fiecare ~1.2s).
            _time, frequency, confidence, _activation = crepe.predict(
                audio,
                sr=sample_rate,
                model_capacity=self.MODEL_CAPACITY,
                viterbi=False,
                verbose=0,
            )

            # Cadrul cu cea mai mare încredere → frecvența reprezentativă
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
