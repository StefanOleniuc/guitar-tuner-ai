import logging
import sys
from datetime import datetime


_EMOJI = {
    "DEBUG": "🔍",
    "INFO": "🚀",
    "WARNING": "🔶",
    "ERROR": "❌",
    "CRITICAL": "❌",
}


class _EmojiFormatter(logging.Formatter):
    """Adaugă emoji corespunzător nivelului de log + timestamp cu milisecunde."""

    def format(self, record: logging.LogRecord) -> str:
        record.msg = f"{_EMOJI.get(record.levelname, '')} {record.msg}"
        return super().format(record)

    def formatTime(self, record: logging.LogRecord, datefmt: str | None = None) -> str:
        """Override pentru a suporta milisecunde în timestamp."""
        dt = datetime.fromtimestamp(record.created)
        return dt.strftime("%H:%M:%S") + f".{int(record.msecs):03d}"


def setup_logging(log_level: str) -> None:
    """Inițializează logging-ul global al aplicației."""
    formatter = _EmojiFormatter(
        fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    )

    # stdout (nu stderr) — Railway/Docker colorează stderr cu roșu și
    # marchează totul ca "error" în UI, chiar și log-urile INFO benigne.
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    root = logging.getLogger()
    root.setLevel(log_level.upper())
    root.handlers.clear()
    root.addHandler(handler)

    # Reducem verbozitatea librăriilor externe
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)