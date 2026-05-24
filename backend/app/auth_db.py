"""Stocare conturi în SQLite — tabelă `users`. Migrabil la PostgreSQL."""

import logging
import os
import sqlite3
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

_DB_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
_DB_PATH = os.path.join(_DB_DIR, "gtune.db")


def _connect() -> sqlite3.Connection:
    os.makedirs(_DB_DIR, exist_ok=True)
    conn = sqlite3.connect(_DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Creează schema dacă nu există. De apelat la pornire.

    Tabele:
      * `users`             — conturi (vezi auth).
      * `user_preferences`  — instrument preferat + calibrare A4 per cont.
                              Sincronizat la login → AppSettings.
      * `tuning_sessions`   — istoric: o sesiune completă de acordaj per rând.
    """
    with _connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                email         TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                display_name  TEXT,
                created_at    TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS user_preferences (
                user_id      INTEGER PRIMARY KEY,
                instrument   TEXT NOT NULL,
                a4           REAL NOT NULL,
                left_handed  INTEGER NOT NULL DEFAULT 0,
                updated_at   TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        # Migrare pentru baze de date create înainte de `left_handed`.
        try:
            conn.execute(
                "ALTER TABLE user_preferences ADD COLUMN left_handed INTEGER NOT NULL DEFAULT 0"
            )
        except sqlite3.OperationalError:
            pass
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS tuning_sessions (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id          INTEGER NOT NULL,
                instrument       TEXT NOT NULL,
                tuning_name      TEXT NOT NULL,
                strings_tuned    INTEGER NOT NULL,
                total_strings    INTEGER NOT NULL,
                duration_seconds REAL NOT NULL,
                a4               REAL NOT NULL DEFAULT 440.0,
                created_at       TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        # Migrare pentru baze de date create înainte de adăugarea coloanei `a4`
        # (instalări existente). SQLite nu are `ADD COLUMN IF NOT EXISTS`,
        # deci ignorăm dacă există deja.
        try:
            conn.execute(
                "ALTER TABLE tuning_sessions ADD COLUMN a4 REAL NOT NULL DEFAULT 440.0"
            )
        except sqlite3.OperationalError:
            pass  # Coloana există deja → migrare deja făcută.
        # Index pentru listare rapidă a ultimelor sesiuni per user.
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_tuning_sessions_user_created "
            "ON tuning_sessions (user_id, created_at DESC)"
        )
    logger.info("🔐 [auth_db] Baza de date pregătită: %s", _DB_PATH)


def create_user(email: str, password_hash: str, display_name: str | None) -> int:
    with _connect() as conn:
        cur = conn.execute(
            "INSERT INTO users (email, password_hash, display_name, created_at) "
            "VALUES (?, ?, ?, ?)",
            (
                email,
                password_hash,
                display_name,
                datetime.now(timezone.utc).isoformat(),
            ),
        )
        return int(cur.lastrowid)


def get_user_by_email(email: str) -> dict | None:
    with _connect() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE email = ?", (email,)
        ).fetchone()
        return dict(row) if row else None


def get_user_by_id(user_id: int) -> dict | None:
    with _connect() as conn:
        row = conn.execute(
            "SELECT * FROM users WHERE id = ?", (user_id,)
        ).fetchone()
        return dict(row) if row else None


def update_display_name(user_id: int, display_name: str | None) -> None:
    """Modifică numele afișat al utilizatorului."""
    with _connect() as conn:
        conn.execute(
            "UPDATE users SET display_name = ? WHERE id = ?",
            (display_name, user_id),
        )


def update_password_hash(email: str, password_hash: str) -> None:
    """Salvează un nou hash de parolă pentru utilizatorul cu adresa dată."""
    with _connect() as conn:
        conn.execute(
            "UPDATE users SET password_hash = ? WHERE email = ?",
            (password_hash, email),
        )


# ─── Preferințe utilizator (instrument preferat + calibrare A4) ──────


def get_preferences(user_id: int) -> dict | None:
    """Întoarce preferințele utilizatorului sau None dacă n-a setat încă."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT instrument, a4, left_handed, updated_at "
            "FROM user_preferences WHERE user_id = ?",
            (user_id,),
        ).fetchone()
        if row is None:
            return None
        d = dict(row)
        # SQLite stochează bool ca 0/1 — convertim la Python bool pentru API.
        d["left_handed"] = bool(d["left_handed"])
        return d


def set_preferences(
    user_id: int,
    instrument: str,
    a4: float,
    left_handed: bool,
) -> None:
    """Upsert peste preferințele utilizatorului."""
    now = datetime.now(timezone.utc).isoformat()
    with _connect() as conn:
        conn.execute(
            """
            INSERT INTO user_preferences
                (user_id, instrument, a4, left_handed, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                instrument  = excluded.instrument,
                a4          = excluded.a4,
                left_handed = excluded.left_handed,
                updated_at  = excluded.updated_at
            """,
            (user_id, instrument, a4, 1 if left_handed else 0, now),
        )


# ─── Istoric sesiuni de acordaj ──────────────────────────────────────


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
        cur = conn.execute(
            """
            INSERT INTO tuning_sessions (
                user_id, instrument, tuning_name,
                strings_tuned, total_strings,
                duration_seconds, a4, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
        return int(cur.lastrowid)


def list_tuning_sessions(user_id: int, limit: int = 20) -> list[dict]:
    """Cele mai recente sesiuni (descrescător după dată), cap la `limit`."""
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT id, instrument, tuning_name,
                   strings_tuned, total_strings,
                   duration_seconds, a4, created_at
            FROM tuning_sessions
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (user_id, limit),
        ).fetchall()
        return [dict(r) for r in rows]


def count_tuning_sessions(user_id: int) -> int:
    """Numărul total de sesiuni — pentru afișaj în profil."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT COUNT(*) AS c FROM tuning_sessions WHERE user_id = ?",
            (user_id,),
        ).fetchone()
        return int(row["c"]) if row else 0
