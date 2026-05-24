from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configurare aplicație citită din .env."""

    ENV: str = "development"
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    LOG_LEVEL: str = "DEBUG"

    # SendGrid HTTPS API pentru trimiterea codurilor OTP de resetare parolă.
    # Necesită „Single Sender Verification" — verifici DOAR adresa de la
    # care trimiți (nu un domeniu), apoi poți trimite către orice destinatar.
    # 100 emailuri/zi gratuit. Vezi https://sendgrid.com.
    SENDGRID_API_KEY: str = ""
    SENDGRID_FROM_EMAIL: str = "gtune.app@gmail.com"
    SENDGRID_FROM_NAME: str = "GTune AI"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
