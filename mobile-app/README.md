# GTune AI — aplicația mobilă (Flutter)

Client mobil al acordorului hibrid **GTune AI**. Rulează algoritmul **YIN** local
(detecție de pitch offline, în timp real) și comunică cu backendul FastAPI pentru
verificarea de înaltă acuratețe cu modelul **CREPE** (modul *AI Precision*).

## Structura
- `lib/services/` — captură audio, YIN (`PitchService`), client API, metronom, autentificare
- `lib/screens/` — ecranele Acordor, Metronom, Cont
- `lib/models/`, `lib/utils/` — modele de date și utilitare (ex. `OneEuroFilter`)
- `test/` — teste unitare (`flutter test`)

## Rulare
```powershell
flutter pub get
flutter run --release        # se conecteaza la backendul din cloud (Railway)
```

Vezi și [README-ul principal](../README.md) al proiectului.
