"""Teste unitare pentru securitatea autentificării.

Rulare: `pytest backend/tests/ -v`
"""
import bcrypt
import pytest

from app.auth_security import (
    create_token,
    decode_token,
    hash_password,
    verify_password,
)


class TestPasswordHashing:
    def test_hash_is_not_plaintext(self):
        h = hash_password("MySecret123")
        assert h != "MySecret123"
        assert h.startswith("$2b$")  # bcrypt prefix

    def test_hash_different_each_time(self):
        # Salt aleator → același password produce hash-uri diferite.
        h1 = hash_password("samepass")
        h2 = hash_password("samepass")
        assert h1 != h2

    def test_verify_correct_password(self):
        h = hash_password("CorrectHorseBatteryStaple")
        assert verify_password("CorrectHorseBatteryStaple", h) is True

    def test_verify_wrong_password(self):
        h = hash_password("real-password")
        assert verify_password("WRONG", h) is False

    def test_verify_invalid_hash_returns_false(self):
        assert verify_password("anything", "not-a-bcrypt-hash") is False


class TestJWT:
    def test_token_roundtrip(self):
        tok = create_token(42)
        assert decode_token(tok) == 42

    def test_token_for_different_users_differ(self):
        assert create_token(1) != create_token(2)

    def test_invalid_token_returns_none(self):
        assert decode_token("not.a.valid.token") is None
        assert decode_token("") is None

    def test_tampered_token_returns_none(self):
        tok = create_token(1)
        tampered = tok[:-4] + "AAAA"
        assert decode_token(tampered) is None
