# GTune AI — Acordor hibrid de chitară (DSP + AI)

**Lucrare de diplomă** · Oleniuc Ștefan
Universitatea Politehnica Timișoara — Facultatea de Automatică și Calculatoare
Coordonator: Ș.l. dr. ing. Stelian Nicola · sesiunea Iulie 2026

## Descriere
Aplicație mobilă de acordaj pentru instrumente cu corzi, cu detecție **hibridă** a
frecvenței fundamentale: algoritmul **YIN** (DSP) rulează local pe telefon (rapid,
offline), iar modelul de inteligență artificială **CREPE** rulează pe un backend
dedicat (precizie ridicată, la cerere). Include 5 instrumente, mod cromatic,
metronom fără derivă și cont opțional cu sincronizare în cloud.

## Repository (cod sursă complet, fără binare compilate)
https://github.com/StefanOleniuc/guitar-tuner-ai

## Structura proiectului
- `mobile-app/` — aplicația **Flutter (Dart)**; codul în `mobile-app/lib/`
  (`services/`, `screens/`, `models/`, `utils/`); teste în `mobile-app/test/`
- `backend/` — serverul **FastAPI (Python)**; codul în `backend/app/`
  (`api/`, `services/`, `auth_security.py`, `auth_db.py`); teste în `backend/tests/`
- `run_dev.ps1`, `backend/run_server.ps1` — scripturi de rulare (dev)

## Tehnologii
Flutter/Dart · FastAPI/Python 3.11 · TensorFlow (CREPE) · PostgreSQL · Docker ·
Railway · JWT (HS256) · bcrypt

## Cerințe
- Flutter SDK (3.x) + Android SDK / dispozitiv Android
- Python 3.11
- (opțional) PostgreSQL local — sau se folosește backendul live de pe Railway

---

## A. Backend (FastAPI + CREPE)

### Instalare
```powershell
cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env      # completeaza GTUNE_JWT_SECRET, DATABASE_URL, SENDGRID_API_KEY
```

### Lansare
```powershell
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
# sau, cu logare + verificare IP LAN:  .\run_server.ps1
```
Verificare: http://localhost:8000/api/health · documentație API: http://localhost:8000/docs

> Detecția de pitch (CREPE) funcționează imediat; funcțiile de cont necesită
> `DATABASE_URL` (PostgreSQL).

## B. Aplicația mobilă (Flutter)

### Instalare
```powershell
cd mobile-app
flutter pub get
```

### Configurarea backendului
- **Release (implicit):** folosește backendul live de pe Railway — nimic de configurat.
- **Debug (backend local):** editează `mobile-app/lib/utils/constants.dart`, câmpul
  `_baseUrlDebug`, cu IP-ul din LAN al laptopului: `http://<IP-LAN>:8000`.

### Lansare
```powershell
flutter run                 # pe dispozitiv/emulator Android
# sau, cu logare:  .\run_dev.ps1   (din radacina proiectului)
```

### Build APK (release)
```powershell
flutter build apk --release
# rezultat: build/app/outputs/flutter-apk/app-release.apk
```

## Testare
```powershell
cd backend     ; pytest          # 21 teste (securitate, validari)
cd mobile-app  ; flutter test    # 28 teste (conversii, One Euro Filter)
```

## Livrabile
- **Cod sursă complet:** acest repository (fără binare compilate).
- **Documentația** (lucrarea de diplomă): depusă separat la facultate.
- **Backend live (demo):** https://guitar-tuner-ai.up.railway.app
