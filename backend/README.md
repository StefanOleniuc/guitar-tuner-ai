# GTune AI — Backend

Serverul FastAPI al aplicației: expune modelul **CREPE** (detecție de pitch) și
gestionează conturile (înregistrare, autentificare JWT, resetare parolă).

## Cerințe
- Python 3.11
- o bază de date PostgreSQL (locală sau în cloud)

## Setup
```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
```
În `.env` completezi valori proprii mediului tău:
- `DATABASE_URL` — conexiunea la PostgreSQL (obligatorie pentru pornirea serverului)
- `GTUNE_JWT_SECRET` — un șir aleatoriu ales de tine, pentru semnarea token-urilor
- `SENDGRID_API_KEY` — opțional, cont SendGrid, doar pentru emailurile de resetare a parolei

## Rulare
```powershell
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## URL-uri utile
| URL | Descriere |
|-----|-----------|
| http://localhost:8000 | Root |
| http://localhost:8000/docs | Swagger UI |
| http://localhost:8000/api/health | Health check |

## Testare
```powershell
pytest
```
