"""Rute de autentificare: înregistrare, login, profil, resetare parolă.

Email + parolă, token JWT. Stocare în SQLite (vezi auth_db).
"""

import json
import logging
import re
import secrets
import smtplib
import socket
from datetime import datetime, timedelta, timezone
from email.mime.text import MIMEText

import dns.exception
import dns.resolver
import httpx
from fastapi import APIRouter, BackgroundTasks, Header, HTTPException
from pydantic import BaseModel, Field

from app import auth_db
from app.auth_security import (
    create_token,
    decode_token,
    hash_password,
    verify_password,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["auth"])

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

# Domenii temporare (temp-mail) — respinse chiar dacă trec DNS.
_DISPOSABLE_DOMAINS: frozenset[str] = frozenset({
    "mailinator.com", "guerrillamail.com", "10minutemail.com",
    "tempmail.com", "temp-mail.org", "throwawaymail.com", "yopmail.com",
    "trashmail.com", "getnada.com", "sharklasers.com", "maildrop.cc",
    "fakemail.net", "dispostable.com", "mailnesia.com", "mintemail.com",
    "spam4.me", "tempr.email", "moakt.com", "emailondeck.com",
})


def _check_email_domain(email: str) -> tuple[bool, str | None]:
    """Verifică MX/A DNS al domeniului — strict: ORICE eșec = respingere.

    Acceptăm DOAR dacă domeniul are explicit MX (sau A ca fallback RFC 5321).
    Timeout, NoNameservers, syntax error → respingem (mai bine un fals
    negativ ocazional decât un cont pe un domeniu inexistent).
    """
    domain = email.rsplit("@", 1)[-1]
    if domain in _DISPOSABLE_DOMAINS:
        return False, "Adresele de email temporare nu sunt acceptate."
    try:
        answers = dns.resolver.resolve(domain, "MX", lifetime=2.5)
        if len(answers) > 0:
            return True, None
        return False, "Domeniul adresei de email nu poate primi mesaje."
    except dns.resolver.NXDOMAIN:
        return False, "Domeniul adresei de email nu există."
    except dns.resolver.NoAnswer:
        # Domeniu fără MX → fallback pe A (RFC 5321).
        try:
            dns.resolver.resolve(domain, "A", lifetime=2.5)
            return True, None
        except dns.exception.DNSException:
            return False, "Domeniul adresei de email nu poate primi mesaje."
    except dns.exception.DNSException as exc:
        # Timeout / NoNameservers / SyntaxError → NU putem confirma că
        # domeniul există → respingem. Bug-ul anterior (btt.ch timeout →
        # acceptat) e închis aici.
        logger.warning(
            "🔶 [auth] DNS pentru '%s' a eșuat (%s) — înregistrare respinsă",
            domain,
            exc.__class__.__name__,
        )
        return False, "Nu am putut verifica domeniul emailului. Folosește o adresă reală și încearcă din nou."


# ─── Modele cerere / răspuns ────────────────────────────────────────
class RegisterRequest(BaseModel):
    email: str
    password: str = Field(..., min_length=6)
    display_name: str | None = Field(None, alias="displayName")


class LoginRequest(BaseModel):
    email: str
    password: str


class ResetRequest(BaseModel):
    email: str


class ResetConfirmRequest(BaseModel):
    email: str
    code: str
    new_password: str = Field(..., min_length=6)


class UserPublic(BaseModel):
    id: int
    email: str
    displayName: str | None


class AuthResponse(BaseModel):
    token: str
    user: UserPublic


def _public(row: dict) -> UserPublic:
    return UserPublic(
        id=row["id"], email=row["email"], displayName=row["display_name"]
    )


def _require_user(authorization: str | None) -> dict:
    """Validează header-ul Bearer și întoarce utilizatorul."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Token de autentificare lipsă")
    user_id = decode_token(authorization[7:])
    if user_id is None:
        raise HTTPException(status_code=401, detail="Sesiune invalidă sau expirată")
    row = auth_db.get_user_by_id(user_id)
    if row is None:
        raise HTTPException(status_code=401, detail="Cont inexistent")
    return row


# ─── Endpoint-uri ───────────────────────────────────────────────────
@router.post("/register", response_model=AuthResponse)
def register(req: RegisterRequest) -> AuthResponse:
    email = req.email.strip().lower()
    if not _EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="Adresă de email invalidă")
    if auth_db.get_user_by_email(email) is not None:
        raise HTTPException(
            status_code=409, detail="Există deja un cont cu acest email"
        )
    # Verificăm că domeniul de email chiar poate primi mesaje (DNS/MX).
    domain_ok, domain_err = _check_email_domain(email)
    if not domain_ok:
        logger.info("🔐 [auth] Înregistrare respinsă (domeniu invalid): %s", email)
        raise HTTPException(status_code=400, detail=domain_err)
    user_id = auth_db.create_user(
        email, hash_password(req.password), req.display_name
    )
    row = auth_db.get_user_by_id(user_id)
    assert row is not None
    logger.info("🔐 [auth] Cont nou creat: %s", email)
    return AuthResponse(token=create_token(user_id), user=_public(row))


@router.post("/login", response_model=AuthResponse)
def login(req: LoginRequest) -> AuthResponse:
    email = req.email.strip().lower()
    row = auth_db.get_user_by_email(email)
    if row is None or not verify_password(req.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="Email sau parolă greșite")
    logger.info("🔐 [auth] Autentificare: %s", email)
    return AuthResponse(token=create_token(row["id"]), user=_public(row))


@router.get("/me", response_model=UserPublic)
def me(authorization: str | None = Header(default=None)) -> UserPublic:
    """Profilul utilizatorului curent — pentru validarea sesiunii salvate."""
    return _public(_require_user(authorization))


class UpdateProfileRequest(BaseModel):
    display_name: str | None = Field(None, alias="displayName", max_length=80)


@router.put("/me", response_model=UserPublic)
def update_me(
    req: UpdateProfileRequest,
    authorization: str | None = Header(default=None),
) -> UserPublic:
    """Modifică profilul (deocamdată doar `displayName`)."""
    row = _require_user(authorization)
    name = (req.display_name or "").strip() or None
    auth_db.update_display_name(row["id"], name)
    updated = auth_db.get_user_by_id(row["id"])
    assert updated is not None
    logger.info("🔐 [auth] Profil actualizat user_id=%d", row["id"])
    return _public(updated)


# ─── Resetare parolă cu OTP ────────────────────────────────────────
# Token-uri stocate în memorie: {email: (code, expires_at)}
# Nu necesită modificări de schemă DB. La restart server token-urile
# expirate sunt pierdute (utilizatorul trebuie să ceară unul nou).
_reset_tokens: dict[str, tuple[str, datetime]] = {}
_OTP_VALID_MINUTES = 15


def _send_via_resend(to_email: str, subject: str, body: str) -> bool:
    """Trimite email prin Resend HTTPS API (folosește httpx).

    Folosim httpx în loc de urllib fiindcă:
      • urllib are User-Agent default ("Python-urllib/3.x") blocat de
        Cloudflare cu eroare 1010 „browser signature banned";
      • urllib face TLS handshake minimal pe care Cloudflare poate să-l
        fingerprintăm și să-l respingă;
      • httpx folosește httpcore + h11 + TLS modern (compatibil Cloudflare).

    Returnează True la succes, False la eșec. NU aruncă excepții.
    """
    from app.config import settings

    if not settings.RESEND_API_KEY:
        logger.warning("🔐 [auth] RESEND_API_KEY lipsește — sar peste Resend")
        return False

    payload = {
        "from": settings.RESEND_FROM,
        "to": [to_email],
        "subject": subject,
        "text": body,
    }
    headers = {
        "Authorization": f"Bearer {settings.RESEND_API_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "GTuneAI-Backend/1.0",
        "Accept": "application/json",
    }

    try:
        logger.info("🔐 [auth] Resend: POST /emails către %s…", to_email)
        with httpx.Client(timeout=15.0, http2=False) as client:
            resp = client.post(
                "https://api.resend.com/emails",
                json=payload,
                headers=headers,
            )
        if 200 <= resp.status_code < 300:
            logger.info(
                "🔐 [auth] Resend OK (status %d): %s",
                resp.status_code,
                resp.text[:200],
            )
            return True
        logger.error(
            "🔐 [auth] Resend HTTP %d: %s",
            resp.status_code,
            resp.text[:500],
        )
        return False
    except httpx.TimeoutException as exc:
        logger.error("🔐 [auth] Resend timeout: %s", exc)
        return False
    except Exception as exc:
        logger.error("🔐 [auth] Resend a eșuat: %s: %s", type(exc).__name__, exc)
        return False


def _send_reset_email(to_email: str, code: str) -> None:
    """Trimite codul OTP. Prioritate: Resend (HTTPS) → SMTP Gmail (fallback).

    Pe Railway/PaaS porturile SMTP sunt blocate → doar Resend funcționează.
    Local, dacă nu ai cheie Resend, se folosește SMTP direct.
    """
    subject = f"GTune AI — Cod resetare parolă: {code}"
    body = (
        f"Codul tău de resetare parolă GTune AI este:\n\n"
        f"  {code}\n\n"
        f"Codul este valabil {_OTP_VALID_MINUTES} minute.\n"
        f"Dacă nu ai cerut resetarea parolei, ignoră acest mesaj."
    )

    # 1) Încercăm Resend (merge și pe Railway).
    if _send_via_resend(to_email, subject, body):
        return

    # 2) Fallback SMTP — doar dacă avem credentiale Gmail și suntem
    #    pe o platformă care permite outbound SMTP (dev local).
    from app.config import settings

    user = settings.GMAIL_USER
    pwd = settings.GMAIL_APP_PASSWORD
    if not user or not pwd:
        logger.error(
            "🔐 [auth] Nicio metodă de trimitere email disponibilă "
            "(RESEND_API_KEY și GMAIL_* sunt goale)"
        )
        return

    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = subject
    msg["From"] = user
    msg["To"] = to_email

    last_exc: Exception | None = None
    # Pe Railway, getaddrinfo() returnează adesea întâi IPv6 pentru
    # smtp.gmail.com, dar containerul nu are conectivitate IPv6 →
    # "Network is unreachable" (Errno 101). Forțăm IPv4 doar pe durata
    # acestei funcții (monkey-patch scoped).
    _orig_getaddrinfo = socket.getaddrinfo

    def _v4_only(host, port, *args, **kwargs):
        return _orig_getaddrinfo(host, port, socket.AF_INET, *args[1:], **kwargs)

    socket.getaddrinfo = _v4_only
    try:
        # Încercăm 587 (STARTTLS) întâi — cel mai des permis pe PaaS.
        try:
            logger.info("🔐 [auth] SMTP: conect la smtp.gmail.com:587 (STARTTLS, IPv4)…")
            with smtplib.SMTP("smtp.gmail.com", 587, timeout=10) as smtp:
                smtp.ehlo()
                smtp.starttls()
                smtp.login(user, pwd)
                smtp.send_message(msg)
            logger.info("🔐 [auth] SMTP: email trimis OK către %s (587)", to_email)
            return
        except Exception as exc:
            last_exc = exc
            logger.warning("🔐 [auth] SMTP 587 a eșuat: %s — încerc 465", exc)

        # Fallback: SMTP_SSL pe 465.
        try:
            logger.info("🔐 [auth] SMTP: conect la smtp.gmail.com:465 (SSL, IPv4)…")
            with smtplib.SMTP_SSL("smtp.gmail.com", 465, timeout=10) as smtp:
                smtp.login(user, pwd)
                smtp.send_message(msg)
            logger.info("🔐 [auth] SMTP: email trimis OK către %s (465)", to_email)
        except Exception as exc:
            logger.error(
                "🔐 [auth] SMTP a eșuat pe ambele porturi (587: %s, 465: %s)",
                last_exc,
                exc,
            )
            raise
    finally:
        socket.getaddrinfo = _orig_getaddrinfo


@router.post("/reset-password")
def reset_password(
    req: ResetRequest, background_tasks: BackgroundTasks
) -> dict[str, str]:
    """Pasul 1: generează OTP și îl trimite pe email.

    Răspuns mereu generic — nu dezvăluim dacă adresa există în baza de date.
    Trimiterea email-ului rulează în background (SMTP poate dura 5–10s pe
    Railway), altfel clientul dă timeout și userul vede „serverul nu răspunde”.
    """
    email = req.email.strip().lower()
    row = auth_db.get_user_by_email(email)
    if row is not None:
        code = f"{secrets.randbelow(1_000_000):06d}"
        _reset_tokens[email] = (
            code,
            datetime.now(timezone.utc) + timedelta(minutes=_OTP_VALID_MINUTES),
        )

        def _send_safe(to: str, c: str) -> None:
            try:
                _send_reset_email(to, c)
            except Exception as exc:
                logger.error("🔐 [auth] Eroare trimitere email reset: %s", exc)

        background_tasks.add_task(_send_safe, email, code)
    logger.info("🔐 [auth] Resetare parolă cerută pentru: %s", email)
    return {
        "message": "Dacă există un cont cu această adresă, "
        "vei primi un cod de resetare pe email.",
    }


@router.post("/reset-confirm")
def reset_confirm(req: ResetConfirmRequest) -> dict[str, str]:
    """Pasul 2: validează codul OTP și actualizează parola."""
    email = req.email.strip().lower()
    entry = _reset_tokens.get(email)
    if (
        entry is None
        or datetime.now(timezone.utc) > entry[1]
        or entry[0] != req.code.strip()
    ):
        raise HTTPException(status_code=400, detail="Cod invalid sau expirat.")
    auth_db.update_password_hash(email, hash_password(req.new_password))
    del _reset_tokens[email]
    logger.info("🔐 [auth] Parolă resetată pentru: %s", email)
    return {"message": "Parola a fost resetată cu succes."}
