# Guitar Tuner AI — Backend

FastAPI backend pentru aplicația mobilă de acordaj.

## Cerințe

- Python 3.11
- pip

## Setup

```powershell
# 1. Creează și activează venv
python -m venv venv
.\venv\Scripts\Activate.ps1

# 2. Instalează dependențele
pip install -r requirements.txt

# 3. Configurare variabile de mediu
copy .env.example .env
# Editează .env dacă e nevoie
```

## Rulare

```powershell
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## URL-uri utile

| URL | Descriere |
|-----|-----------|
| http://localhost:8000 | Root |
| http://localhost:8000/docs | Swagger UI |
| http://localhost:8000/redoc | ReDoc |
| http://localhost:8000/api/health | Health check |
