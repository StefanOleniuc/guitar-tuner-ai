from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configurare aplicație citită din .env."""

    ENV: str = "development"
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    LOG_LEVEL: str = "DEBUG"

    # Gmail SMTP pentru trimiterea codurilor OTP de resetare parolă
    # (folosit doar local; în producție Resend e prioritar fiindcă
    # Railway blochează outbound SMTP).
    GMAIL_USER: str = ""
    GMAIL_APP_PASSWORD: str = ""

    # Resend HTTPS API — alternativă la SMTP pentru PaaS-uri care
    # blochează porturile 25/465/587 (Railway, Heroku, Render etc.).
    # 100 emailuri/zi gratuit. Vezi https://resend.com.
    RESEND_API_KEY: str = ""
    RESEND_FROM: str = "GTune AI <onboarding@resend.dev>"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
