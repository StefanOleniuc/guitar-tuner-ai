"""Stocare conturi / preferințe / istoric în PostgreSQL.

Folosim psycopg2 direct (fără ORM) — query-uri simple, cod transparent.
Conexiunea se obține din `DATABASE_URL` (setat automat de plugin-ul
Postgres pe Railway).
"""

import logging
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Iterator

import psycopg2
from psycopg2.extensions import connection as PgConnection
from psycopg2.extras import RealDictCursor

from app.config import settings

logger = logging.getLogger(__name__)


@contextmanager
def _connect() -> Iterator[PgConnection]:
    """Deschide o conexiune PostgreSQL și o închide automat la final.

    Cursorul implicit va întoarce rânduri ca `dict` (RealDictCursor),
    pentru compatibilitate cu codul restului aplicației.
    """
    if not settings.DATABASE_URL:
        raise RuntimeError(
            "DATABASE_URL lipsește — setează-l în .env sau în variabilele Railway"
        )
    conn = psycopg2.connect(settings.DATABASE_URL, cursor_factory=RealDictCursor)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db() -> None:
    """Creează schema dacă nu există. De apelat la pornire.

    Tabele:
      * `users`             — conturi (vezi auth).
      * `user_preferences`  — instrument preferat + calibrare A4 per cont.
      * `tuning_sessions`   — istoric: o sesiune completă de acordaj per rând.
    """
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id            SERIAL PRIMARY KEY,
                email         TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                display_name  TEXT,
                created_at    TEXT NOT NULL
            )
            """
        )
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS user_preferences (
                user_id      INTEGER PRIMARY KEY
                              REFERENCES users(id) ON DELETE CASCADE,
                instrument   TEXT NOT NULL,
                a4           REAL NOT NULL,
                left_handed  BOOLEAN NOT NULL DEFAULT FALSE,
                updated_at   TEXT NOT NULL
            )
            """
        )
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS tuning_sessions (
                id               SERIAL PRIMARY KEY,
                user_id          INTEGER NOT NULL
                                  REFERENCES users(id) ON DELETE CASCADE,
                instrument       TEXT NOT NULL,
                tuning_name      TEXT NOT NULL,
                strings_tuned    INTEGER NOT NULL,
                total_strings    INTEGER NOT NULL,
                duration_seconds REAL NOT NULL,
                a4               REAL NOT NULL DEFAULT 440.0,
                created_at       TEXT NOT NULL
            )
            """
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_tuning_sessions_user_created "
            "ON tuning_sessions (user_id, created_at DESC)"
        )
    logger.info("[auth_db] Schema PostgreSQL pregătită")


# Conturi


def create_user(email: str, password_hash: str, display_name: str | None) -> int:
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO users (email, password_hash, display_name, created_at) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            (
                email,
                password_hash,
                display_name,
                datetime.now(timezone.utc).isoformat(),
            ),
        )
        return int(cur.fetchone()["id"])


def get_user_by_email(email: str) -> dict | None:
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute("SELECT * FROM users WHERE email = %s", (email,))
        row = cur.fetchone()
        return dict(row) if row else None


def get_user_by_id(user_id: int) -> dict | None:
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        row = cur.fetchone()
        return dict(row) if row else None


def update_display_name(user_id: int, display_name: str | None) -> None:
    """Modifică numele afișat al utilizatorului."""
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            "UPDATE users SET display_name = %s WHERE id = %s",
            (display_name, user_id),
        )


def update_password_hash(email: str, password_hash: str) -> None:
    """Salvează un nou hash de parolă pentru utilizatorul cu adresa dată."""
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            "UPDATE users SET password_hash = %s WHERE email = %s",
            (password_hash, email),
        )


# Preferințe utilizator (instrument preferat + calibrare A4)


def get_preferences(user_id: int) -> dict | None:
    """Întoarce preferințele utilizatorului sau None dacă n-a setat încă."""
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT instrument, a4, left_handed, updated_at "
            "FROM user_preferences WHERE user_id = %s",
            (user_id,),
        )
        row = cur.fetchone()
        return dict(row) if row else None


def set_preferences(
    user_id: int,
    instrument: str,
    a4: float,
    left_handed: bool,
) -> None:
    """Upsert peste preferințele utilizatorului."""
    now = datetime.now(timezone.utc).isoformat()
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO user_preferences
                (user_id, instrument, a4, left_handed, updated_at)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (user_id) DO UPDATE SET
                instrument  = EXCLUDED.instrument,
                a4          = EXCLUDED.a4,
                left_handed = EXCLUDED.left_handed,
                updated_at  = EXCLUDED.updated_at
            """,
            (user_id, instrument, a4, left_handed, now),
        )


# Istoric sesiuni de acordaj


def add_tuning_session(
    user_id: int,
    instrument: str,
    tuning_name: str,
    strings_tuned: int,
    total_strings: int,
    duration_seconds: float,
    a4: float,
) -> int:
    """Inserează o sesiune completă; întoarce ID-ul ei."""
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO tuning_sessions (
                user_id, instrument, tuning_name,
                strings_tuned, total_strings,
                duration_seconds, a4, created_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
            """,
            (
                user_id,
                instrument,
                tuning_name,
                strings_tuned,
                total_strings,
                duration_seconds,
                a4,
                datetime.now(timezone.utc).isoformat(),
            ),
        )
        return int(cur.fetchone()["id"])


def list_tuning_sessions(user_id: int, limit: int = 20) -> list[dict]:
    """Cele mai recente sesiuni (descrescător după dată), cap la `limit`."""
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT id, instrument, tuning_name,
                   strings_tuned, total_strings,
                   duration_seconds, a4, created_at
            FROM tuning_sessions
            WHERE user_id = %s
            ORDER BY created_at DESC
            LIMIT %s
            """,
            (user_id, limit),
        )
        return [dict(r) for r in cur.fetchall()]


def count_tuning_sessions(user_id: int) -> int:
    """Numărul total de sesiuni — pentru afișaj în profil."""
    with _connect() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT COUNT(*) AS c FROM tuning_sessions WHERE user_id = %s",
            (user_id,),
        )
        row = cur.fetchone()
        return int(row["c"]) if row else 0
