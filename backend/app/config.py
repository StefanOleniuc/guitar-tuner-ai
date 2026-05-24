from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configurare aplicație citită din .env."""

    ENV: str = "development"
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    LOG_LEVEL: str = "DEBUG"

    # Gmail SMTP pentru trimiterea codurilor OTP de resetare parolă.
    GMAIL_USER: str = ""
    GMAIL_APP_PASSWORD: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
