# GTune AI — Acordor hibrid de chitară (DSP + AI)

**Lucrare de diplomă**

- **Autor:** Oleniuc Ștefan
- **Universitate:** Politehnica Timișoara — Facultatea de Automatică și Calculatoare
- **Coordonator:** Ș.l. dr. ing. Stelian Nicola
- **Sesiune:** Iulie 2026

## Descriere
Aplicație mobilă de acordaj pentru instrumente cu corzi, cu detecție **hibridă** a
frecvenței fundamentale: algoritmul **YIN** (DSP) rulează local pe telefon (rapid,
offline), iar modelul de inteligență artificială **CREPE** rulează pe un backend
dedicat, desfășurat în cloud (precizie ridicată, la cerere). Include 5 instrumente,
mod cromatic, metronom fără derivă și cont opțional cu sincronizare în cloud.

## Repository
https://github.com/StefanOleniuc/guitar-tuner-ai

## Structura proiectului
- `mobile-app/` — aplicația **Flutter (Dart)**; codul în `mobile-app/lib/`
  (`services/`, `screens/`, `models/`, `utils/`); teste în `mobile-app/test/`
- `backend/` — serverul **FastAPI (Python)**; codul în `backend/app/`
  (`api/`, `services/`, `auth_security.py`, `auth_db.py`); teste în `backend/tests/`

## Tehnologii
Flutter/Dart · FastAPI/Python 3.11 · TensorFlow (CREPE) · PostgreSQL · Docker ·
Railway · JWT (HS256) · bcrypt

## Cerințe
- Flutter SDK (canal *stable*, Dart ≥ 3.11) + Android SDK sau dispozitiv Android
- Python 3.11 — doar pentru rularea locală a backendului

---

## Rulare — aplicația mobilă (Flutter)
Aplicația se conectează la backendul desfășurat în cloud (Railway), deci nu necesită
nicio configurare a serverului.
```powershell
cd mobile-app
flutter pub get
flutter run --release        # pe un dispozitiv/emulator Android
```
Generarea pachetului de instalare (APK):
```powershell
flutter build apk --release
# rezultat: build/app/outputs/flutter-apk/app-release.apk
```

## Rulare — backend (FastAPI + CREPE)
Backendul este deja desfășurat în cloud pe **Railway** (împachetat Docker) și este
folosit automat de aplicație. Pentru rularea locală, în scop de dezvoltare:
```powershell
cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env       # completeaza GTUNE_JWT_SECRET, DATABASE_URL, SENDGRID_API_KEY
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```
Verificare: http://localhost:8000/api/health · documentație API: http://localhost:8000/docs
Funcțiile de cont necesită o bază de date PostgreSQL (`DATABASE_URL`).

## Testare
```powershell
cd backend     ; pytest          # 21 teste (securitate, validari)
cd mobile-app  ; flutter test    # 28 teste (conversii, One Euro Filter)
```

## Livrabile
- **Cod sursă complet al aplicației** — acest repository, fără binare compilate.
- **Documentația** (lucrarea de diplomă) — depusă separat la facultate.
- **Backend live:** https://guitar-tuner-ai.up.railway.app
