import logging
import sys
from datetime import datetime


class _MillisFormatter(logging.Formatter):
    """Formatter cu timestamp în milisecunde."""

    def formatTime(self, record: logging.LogRecord, datefmt: str | None = None) -> str:
        dt = datetime.fromtimestamp(record.created)
        return dt.strftime("%H:%M:%S") + f".{int(record.msecs):03d}"


def setup_logging(log_level: str) -> None:
    """Inițializează logging-ul global al aplicației."""
    formatter = _MillisFormatter(
        fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    )

    # stdout (nu stderr): Railway/Docker marchează stderr ca "error" în UI,
    # chiar și pentru log-urile INFO benigne.
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    root = logging.getLogger()
    root.setLevel(log_level.upper())
    root.handlers.clear()
    root.addHandler(handler)

    # Reducem verbozitatea librăriilor externe.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
