"""Teste pentru validarea emailului (regex + blacklist disposable)."""
import pytest

from app.api.auth import _DISPOSABLE_DOMAINS, _EMAIL_RE


class TestEmailRegex:
    @pytest.mark.parametrize("email", [
        "user@example.com",
        "first.last@domain.ro",
        "x@y.z",
        "name+tag@gmail.com",
    ])
    def test_valid_emails(self, email):
        assert _EMAIL_RE.match(email) is not None

    @pytest.mark.parametrize("email", [
        "no-at-sign.com",
        "@no-local.com",
        "missing-domain@",
        "no-tld@domain",
        "spaces in@email.com",
        "double@@at.com",
    ])
    def test_invalid_emails(self, email):
        assert _EMAIL_RE.match(email) is None


class TestDisposableBlacklist:
    def test_known_disposable_domains_blocked(self):
        for d in ["mailinator.com", "10minutemail.com", "yopmail.com"]:
            assert d in _DISPOSABLE_DOMAINS

    def test_legitimate_domains_not_in_blacklist(self):
        for d in ["gmail.com", "yahoo.com", "outlook.com", "upt.ro"]:
            assert d not in _DISPOSABLE_DOMAINS
