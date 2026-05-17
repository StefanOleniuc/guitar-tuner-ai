# Guitar Tuner AI — Context Document

> **CITEȘTE ACEST FIȘIER PRIMUL** la fiecare sesiune nouă.
> Conține tot ce trebuie să știi despre proiect.

---

## 📋 Despre Proiect

**Titlu:** Aplicație mobilă de tuner pentru chitară și instrumente cu coarde, bazată pe model AI pentru detecția precisă a notelor muzicale.

**Autor:** Oleniuc Ștefan
**Universitate:** Universitatea Politehnica Timișoara
**Specializare:** Ingineria Sistemelor
**Anul:** 2026
**Termen predare:** 30 mai 2026

**Descriere:** Aplicație mobilă (Android, build cross-platform Flutter) care detectează frecvența notelor cântate la chitară (sau alte instrumente cu coarde) folosind o combinație hibridă de algoritmi:
- **YIN** (algoritm DSP clasic, rulează LOCAL pe telefon, instant)
- **CREPE** (Convolutional Neural Network, rulează pe BACKEND când e internet, precizie ±1 cent)

---

## 🏗️ Arhitectură
┌─────────────────────────────────────────────────────┐
│                                                     │
│  📱 APLICAȚIE MOBILĂ (Flutter + Dart)               │
│     ✓ UI complet, captură audio, YIN local         │
│     ✓ Funcționează offline (cu YIN)                │
│            ↓ HTTP REST API                          │
│                                                     │
│  🐍 BACKEND (FastAPI + Python 3.11)                 │
│     ✓ Endpoint /detect-pitch (CREPE)                │
│     ✓ Endpoint /auth (JWT)                          │
│     ✓ Endpoint /sessions, /tunings (CRUD)           │
│            ↓                                        │
│                                                     │
│  🧠 MODEL AI: CREPE pre-antrenat (TensorFlow)       │
│     ✓ Pitch detection cu acuratețe ±1 cent          │
│                                                     │
│  🗄️ BAZĂ DE DATE: PostgreSQL                        │
│     ✓ users, tunings, sessions                      │
│                                                     │
│  ☁️ DEPLOY: Railway (gratuit, conectat la GitHub)   │
│                                                     │
└─────────────────────────────────────────────────────┘

---

## 🛠️ Stack Tehnologic

### Frontend Mobil:
- **Flutter SDK 3.41.9** (canal stable)
- **Dart 3.11.5**
- Pachete principale (de adăugat pe parcurs):
  - `record` — captură audio din microfon
  - `permission_handler` — permisiuni microfon
  - `http` — comunicare cu backend
  - `flutter_secure_storage` — JWT token
  - `audioplayers` — pentru metronom + reference sounds
  - `logger` — logging structurat

### Backend:
- **Python 3.11** (NU 3.14 — incompatibil cu CREPE/TensorFlow)
- **FastAPI** — framework REST API
- **Uvicorn** — server ASGI
- **SQLAlchemy** — ORM pentru PostgreSQL
- **Pydantic** — validare date
- **PyJWT** — autentificare JWT
- **bcrypt** — hashing parole
- **CREPE** — model AI pitch detection
- **librosa** — procesare audio
- **NumPy + SciPy** — calcule matematice

### Database:
- **PostgreSQL** (local pentru dezvoltare, Railway pentru producție)

### Tools:
- **VS Code** — editor principal
- **Android Studio** — pentru SDK + emulator
- **Git + GitHub** — versionare cod
- **Railway** — deploy backend

---

## 📂 Structura Repository
guitar-tuner-ai/
├── CONTEXT.md              ← acest fișier
├── PROGRESS.md             ← log zilnic progres (de creat)
├── README.md               ← descriere generală
├── .gitignore
├── mobile-app/             ← Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/        ← ecrane UI
│   │   ├── widgets/        ← componente reutilizabile
│   │   ├── services/       ← logica business
│   │   ├── models/         ← modele de date
│   │   └── utils/          ← utilități
│   ├── pubspec.yaml
│   └── android/, ios/, etc.
├── backend/                ← FastAPI app (de creat)
│   ├── main.py
│   ├── app/
│   │   ├── api/
│   │   ├── models/
│   │   ├── services/
│   │   └── database.py
│   ├── requirements.txt
│   └── tests/
├── ai-model/               ← Notebook-uri Colab (de creat)
│   └── crepe_evaluation.ipynb
└── docs/                   ← Documentație lucrare (de creat)
├── capitol_1_introducere.md
├── capitol_2_stadiul_actual.md
└── ...

---

## ✅ Funcționalități Aplicație

### 🔵 CORE (esențial):
- [x] Setup proiect Flutter
- [ ] Captură audio din microfon
- [ ] YIN local (Dart) — pitch detection offline
- [ ] AI Precision Mode (CREPE prin backend)
- [ ] UI vizual chitară cu acul tunerului dinamic
- [ ] Mod AUTO (auto-detect coardă)
- [ ] Mod MANUAL (selecție coardă)
- [ ] Multi-instrument (chitară, bas, ukulele, vioară)
- [ ] Multi-acordaj (Standard, Drop D, Open G, DADGAD, custom)
- [ ] Play reference sound pentru fiecare coardă

### 🟢 DIFERENȚIATORI:
- [ ] Metronom (cu BPM ajustabil)
- [ ] Chord Library (~30-50 acorduri cu imagini + sunet)

### 🟡 OPȚIONAL (cu cont):
- [ ] Autentificare JWT
- [ ] Istoric sesiuni acordare
- [ ] Acordaje custom salvate
- [ ] Sincronizare între dispozitive (auto cu cont)

### 🟠 SETĂRI:
- [ ] Tema light/dark
- [ ] Cont (login/logout/profile)
- [ ] Despre / Contact
- [ ] A4 reference (440 Hz default)

## 🤖 REGULI PENTRU AI (Claude / GitHub Copilot / etc.)

### REGULA #1 — Bucăți mici, NU tot proiectul deodată
### REGULA #2 — Logging la fiecare pas

**Tot codul generat TREBUIE să folosească AppLogger.**

Avem un sistem custom de logging deja implementat în `lib/utils/app_logger.dart`.

În Flutter (Dart):
```dart
import '../utils/app_logger.dart';

AppLogger.d('🔍 [ServiceName] Action started: details');   // debug
AppLogger.i('🚀 [ServiceName] Info message');              // info
AppLogger.w('🔶 [ServiceName] Warning: something unusual'); // warning
AppLogger.e('❌ [ServiceName] Error', error: e, stackTrace: st); // error
```

**Caracteristici:**
- Mesajele primesc automat prefix `[APP_LOG]` pentru filtrare
- `kDebugMode` activ — log-urile sunt sărite automat în release (zero overhead)
- Format: `[APP_LOG] [LEVEL] HH:mm:ss.SSS - mesaj`
- Folosește `debugPrint` (nu `print` simplu) — nu trunchiază mesaje lungi

**Convenție emoji:**
- 🔍 Debug (detalii tehnice)
- 🚀 Start/launch
- 🎨 Build/UI render
- 👆 User interaction
- 🎤 Audio capture
- 🌐 HTTP request
- 💾 Database/storage
- ✅ Success
- 🔶 Warning
- ❌ Error
- 🎸 Tuner-specific
- 🥁 Metronom

**În Python (Backend):**
```python
import logging
logger = logging.getLogger(__name__)

logger.debug("🔍 [service_name] Action started: details")
logger.info("🚀 [service_name] Info message")
logger.warning("🔶 [service_name] Warning")
logger.error("❌ [service_name] Error", exc_info=True)
```

### REGULA #2.5 — Workflow dev cu logging

Pentru rulare cu salvare automată log-uri (debugging cu AI):
```powershell
.\run_dev.ps1
```

Generează 2 fișiere per sesiune:
- `dev_logs/session_TIMESTAMP_FULL.txt` — tot output-ul
- `dev_logs/session_TIMESTAMP_APP.txt` — doar liniile cu `[APP_LOG]` (curat)

Pentru AI debugging: citește `_APP.txt` (curat și scurt).
```

### REGULA #3 — Cod citibil, comentat la pași non-triviali

```dart
// ✅ BUN
// Convertim Hz în cenți față de nota țintă
// Formula: cents = 1200 * log2(detected / target)
final cents = 1200 * (math.log(detectedHz / targetHz) / math.ln2);
```

### REGULA #4 — Diacritice românești în UI

Tot textul afișat utilizatorului trebuie cu diacritice corecte:
- ✅ `"Acordare reușită"`
- ❌ `"Acordare reusita"`

### REGULA #5 — Convenții naming

**Dart/Flutter:**
- Files: `snake_case.dart`
- Classes: `PascalCase`
- Variables: `camelCase`
- Constants: `kCamelCase` sau `SCREAMING_SNAKE_CASE`

**Python:**
- Files: `snake_case.py`
- Classes: `PascalCase`
- Variables: `snake_case`
- Constants: `SCREAMING_SNAKE_CASE`

### REGULA #6 — Stop la prima eroare

Dacă ceva nu merge după implementare:
1. **NU genera mai mult cod**
2. **Trimite log-urile complete** la AI/dev
3. **Debug pas cu pas**
4. Doar după ce funcționează → mergi mai departe

---

---

## 🎯 Status implementare

**Ultimă actualizare:** 14 mai 2026

### Faza curentă: AUDIO CAPTURE FUNCȚIONAL → URMEAZĂ PITCH DETECTION (YIN)

### Ce e GATA:
- ✅ Mediu dezvoltare: Flutter + Android Studio + VS Code
- ✅ Telefon Motorola edge 20 conectat (USB debugging)
- ✅ Repository GitHub: StefanOleniuc/guitar-tuner-ai
- ✅ Aplicație Flutter cu schelet curat (main.dart, HomeScreen)
- ✅ AppLogger funcțional ([APP_LOG] tag, debugPrint)
- ✅ Sistem dev logging cu run_dev.ps1 (FULL + APP fișiere)
- ✅ Tema dark, Material 3
- ✅ Backend FastAPI:
  - Structură completă (app/, api/, core/, models/, services/)
  - Endpoint /api/health funcțional
  - Logging structurat cu emoji
  - Configurare prin .env (pydantic-settings)
  - Script run_server.ps1 cu UTF-8 encoding fix
- ✅ Conectare Flutter ↔ Backend:
  - ApiService cu http package
  - ApiConstants pentru URL-uri (debug vs prod)
  - HealthResponse model cu factory.fromJson
  - Buton "🌐 Test Backend Connection" funcțional
  - Verificare reușită pe telefon: răspuns JSON de la backend
- ✅ Captură audio din microfon:
  - AudioService cu pachetele `record` + `permission_handler`
  - Permisiuni microfon Android (AndroidManifest.xml)
  - Stream<Uint8List> de chunks audio PCM16, 16kHz, mono
  - UI cu buton 🎤/⏹️ (verde/roșu)
  - Card cu statistici live: bytes, samples, durată
- ✅ Volume meter (RMS):
  - AudioUtils.calculateRMS() — Root Mean Square din PCM16
  - AudioUtils.rmsToNormalized() — interval [0.0, 1.0]
  - LinearProgressIndicator color-coded:
    - Verde 0-30%
    - Galben 30-70%
    - Roșu peste 70%
  - Peak volume tracker

### În LUCRU:
- 🔄 Pitch detection cu algoritm YIN (URMEAZĂ - sesiune dedicată)

### URMEAZĂ (în ordine):
1. **YIN algorithm în Dart** (Pitch detection local, offline)
   - Implementare difference function
   - CMNDF (Cumulative Mean Normalized Difference Function)
   - Interpolare parabolică pentru precizie sub-sample
   - Output: frecvența fundamentală în Hz
2. Conectare YIN cu stream audio (pipeline complet: mic → YIN → frecvență)
3. UI tuner: afișare notă detectată + cenți față de țintă
4. Multi-instrument + multi-acordaj (chitară, bas, ukulele, vioară)
5. UI vizual chitară (acul tunerului dinamic)
6. Backend: integrare CREPE (model AI pitch detection)
7. Backend: autentificare JWT + database PostgreSQL
8. Funcționalități extra: Metronom + Chord Library
9. Deploy backend pe Railway
10. Testing + Documentație lucrare

### Reguli pentru AI (Claude din VS Code):
- NU genera tot proiectul deodată
- NU genera cod exemplu/demo - doar cod care va rămâne în aplicația finală
- Mereu cu logging [APP_LOG] / Python logging cu emoji
- Diacritice românești în UI
- Citește contextul înainte să generezi orice
- Cod cu comentarii pe părți non-triviale (matematică, algoritmi)
- Pentru fiecare bucată: explicații linie cu linie după

### Concepte stăpânite (verificate prin Q&A):
- ✅ Future / async / await (cod asincron, nu blochează UI)
- ✅ mounted (siguranță setState după await)
- ✅ kDebugMode vs kReleaseMode (cod diferit dev vs prod)
- ✅ factory constructor (conversie JSON → obiect Dart)
- ✅ RMS (Root Mean Square — calcul volum audio)

### Concepte de învățat (sesiunile următoare):
- 🔄 Algoritm YIN (autocorrelation, CMNDF, octave errors)
- 🔄 FFT și spectrograme
- 🔄 CNN și CREPE
- 🔄 JWT și securitate API
- 🔄 SQLAlchemy ORM

---

## 📚 Referințe Cheie (pentru lucrarea scrisă)

### Algoritmi:
- **YIN:** de Cheveigné, A., & Kawahara, H. (2002). YIN, a fundamental frequency estimator for speech and music. *Journal of the Acoustical Society of America, 111*(4), 1917-1930.
- **CREPE:** Kim, J. W., Salamon, J., Li, P., & Bello, J. P. (2018). CREPE: A Convolutional Representation for Pitch Estimation. *Proceedings of the IEEE ICASSP 2018*, 161-165.

### Cărți DSP:
- Smith, J. O. (2007). *Mathematics of the DFT.* Stanford CCRMA.
- Müller, M. (2015). *Fundamentals of Music Processing.* Springer.

### Framework-uri:
- Flutter Documentation: https://docs.flutter.dev
- FastAPI Documentation: https://fastapi.tiangolo.com
- CREPE GitHub: https://github.com/marl/crepe

---

## 🎓 Coordonator Lucrare

**Cerințe documentație** (din Draft_documentatie_licenta.pdf):
1. Introducere (2-3 pagini)
2. Stadiul actual (max 15 pagini, cu tabel comparativ)
3. Bazele teoretice (max 5 pagini)
4. Soluția propusă (arhitectură + diagrame + cazuri utilizare + BD)
5. Implementare (toate funcționalitățile + cod + explicații)
6. Testare (Cypress menționat — DAR poate fi înlocuit cu Flutter integration tests)
7. Concluzii (1-2 pagini)
8. Bibliografie

**Total:** ~50 pagini, scris cu diacritice ă/î/â/ș/ț, citări [nr] în bibliografie.

---

## 🔗 Link-uri utile

- GitHub: https://github.com/StefanOleniuc/guitar-tuner-ai