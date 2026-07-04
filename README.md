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
- **Git**
- **Flutter SDK** (canal *stable*, Dart ≥ 3.11) și mediul de dezvoltare Android
  (Android Studio / Android SDK) — ghid oficial de instalare:
  https://docs.flutter.dev/get-started/install
- **Python 3.11** — necesar doar pentru rularea locală a backendului

---

## Instalare și rulare

### 1. Clonează repository-ul
```powershell
git clone https://github.com/StefanOleniuc/guitar-tuner-ai.git
cd guitar-tuner-ai
```

### 2. Aplicația mobilă (Flutter)
Se conectează automat la backendul desfășurat în cloud (Railway) — nu necesită
configurarea unui server.
```powershell
cd mobile-app
flutter pub get
flutter run --release        # pe un dispozitiv/emulator Android conectat
```
Generarea pachetului de instalare (APK):
```powershell
flutter build apk --release
# rezultat: build/app/outputs/flutter-apk/app-release.apk
```

### 3. Backend (deja desfășurat pe Railway)
Backendul (FastAPI + CREPE) rulează în cloud pe Railway și este folosit automat de
aplicație — nu trebuie pornit separat. Codul sursă este în `backend/`; pentru rularea
locală, în scop de dezvoltare, vezi `backend/README.md`.

## Testare
```powershell
cd backend     ; pytest          # 21 teste (securitate, validari)
cd mobile-app  ; flutter test    # 28 teste (conversii, One Euro Filter)
```

## Livrabile
- **Aplicația mobilă** (Flutter/Dart) — `mobile-app/`
- **Backendul** (FastAPI/Python + model CREPE), desfășurat pe Railway — `backend/`
- **Suita de teste automate** (49 de teste) — `mobile-app/test/`, `backend/tests/`

Codul sursă complet se află în acest repository, fără fișiere binare compilate.
Backendul rulează live la https://guitar-tuner-ai.up.railway.app
