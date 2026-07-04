import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/instrument.dart';
import '../utils/app_logger.dart';
import 'user_data_service.dart';

/// Preferințele aplicației, persistate cu `shared_preferences`.
/// Singleton `ChangeNotifier` — încărcat o dată la pornire în `main()`.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // A4: 440 Hz standard ISO 16. Gamă 415–466 Hz.
  static const double defaultA4 = 440;
  static const double minA4 = 415;
  static const double maxA4 = 466;

  static const String _kInstrument = 'settings.instrumentId';
  static const String _kA4 = 'settings.a4';
  static const String _kShowFrequency = 'settings.showFrequency';
  static const String _kWelcomeSeen = 'settings.welcomeSeen';
  static const String _kLeftHanded = 'settings.leftHanded';
  static const String _kChromatic = 'settings.chromaticMode';

  String _instrumentId = Instrument.guitar.id;
  double _a4 = defaultA4;
  bool _showFrequency = true;
  bool _welcomeSeen = false;
  bool _leftHanded = false;
  bool _chromaticMode = false;

  String get instrumentId => _instrumentId;
  Instrument get instrument => Instrument.byId(_instrumentId);
  double get a4 => _a4;

  /// Dacă afișăm frecvența (Hz) sub notă în tuner.
  bool get showFrequency => _showFrequency;

  /// Dacă utilizatorul a văzut deja ecranul de întâmpinare.
  bool get welcomeSeen => _welcomeSeen;

  /// Modul stângaci: oglindește ordinea corzilor (cea joasă în dreapta).
  bool get leftHanded => _leftHanded;

  /// Mod cromatic: tunerul detectează ORICE notă (84 multi-octavă), nu
  /// doar corzile instrumentului. Setarea e LOCALĂ — nu sincronizăm la
  /// cont (e o preferință de sesiune, nu de profil).
  bool get chromaticMode => _chromaticMode;

  /// Încărcare din storage. De apelat o dată în `main()`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _instrumentId = prefs.getString(_kInstrument) ?? Instrument.guitar.id;
      _a4 = (prefs.getDouble(_kA4) ?? defaultA4).clamp(minA4, maxA4);
      _showFrequency = prefs.getBool(_kShowFrequency) ?? true;
      _welcomeSeen = prefs.getBool(_kWelcomeSeen) ?? false;
      _leftHanded = prefs.getBool(_kLeftHanded) ?? false;
      _chromaticMode = prefs.getBool(_kChromatic) ?? false;
      AppLogger.i(
        '[AppSettings] Încărcat: instrument=$_instrumentId, '
        'A4=${_a4.toStringAsFixed(0)} Hz, freq=$_showFrequency, '
        'leftHanded=$_leftHanded',
      );
    } catch (e) {
      AppLogger.e(
        '[AppSettings] Eroare la încărcare — folosesc default',
        error: e,
      );
    }
    notifyListeners();
  }

  Future<void> setInstrument(String id) async {
    if (_instrumentId == id) return;
    _instrumentId = id;
    AppLogger.i('[AppSettings] Instrument → $id');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kInstrument, id);
    } catch (e) {
      AppLogger.e('[AppSettings] Nu am putut salva instrumentul', error: e);
    }
    // Dacă userul e logat, sincronizăm preferințele și în cloud — fire-and-forget,
    // nu blocăm UI-ul. Necunoaștere a cont = no-op.
    unawaited(UserDataService.instance.pushPreferencesFromSettings());
  }

  Future<void> setA4(double value) async {
    final v = value.clamp(minA4, maxA4).toDouble();
    if (v == _a4) return;
    _a4 = v;
    AppLogger.i('[AppSettings] A4 → ${v.toStringAsFixed(0)} Hz');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kA4, v);
    } catch (e) {
      AppLogger.e('[AppSettings] Nu am putut salva A4', error: e);
    }
    unawaited(UserDataService.instance.pushPreferencesFromSettings());
  }

  void resetA4() => setA4(defaultA4);

  /// Resetează preferințele NEPERSONALE la default (instrument + A4).
  /// Apelat la logout — datele legate de cont nu mai sunt relevante.
  /// `showFrequency` și `welcomeSeen` rămân (sunt setări locale, nu cont).
  Future<void> resetToDefaults() async {
    if (_instrumentId == Instrument.guitar.id &&
        _a4 == defaultA4 &&
        !_leftHanded) {
      return;
    }
    _instrumentId = Instrument.guitar.id;
    _a4 = defaultA4;
    _leftHanded = false;
    AppLogger.i('[AppSettings] Reset la default (logout)');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kInstrument, _instrumentId);
      await prefs.setDouble(_kA4, _a4);
      await prefs.setBool(_kLeftHanded, _leftHanded);
    } catch (e) {
      AppLogger.e('[AppSettings] Nu am putut salva reset-ul', error: e);
    }
    // NU împingem la backend — userul e deja delogat, token-ul e nul.
  }

  /// Marchează ecranul de întâmpinare ca văzut (nu se mai arată automat).
  Future<void> markWelcomeSeen() async {
    if (_welcomeSeen) return;
    _welcomeSeen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kWelcomeSeen, true);
    } catch (e) {
      AppLogger.e('[AppSettings] Nu am putut salva welcomeSeen', error: e);
    }
  }

  Future<void> setLeftHanded(bool value) async {
    if (_leftHanded == value) return;
    _leftHanded = value;
    AppLogger.i('[AppSettings] Stângaci → $value');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLeftHanded, value);
    } catch (e) {
      AppLogger.e('[AppSettings] Nu am putut salva leftHanded', error: e);
    }
    unawaited(UserDataService.instance.pushPreferencesFromSettings());
  }

  Future<void> setChromaticMode(bool value) async {
    if (_chromaticMode == value) return;
    _chromaticMode = value;
    AppLogger.i('[AppSettings] Mod cromatic → $value');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kChromatic, value);
    } catch (e) {
      AppLogger.e('[AppSettings] Nu am putut salva cromaticMode', error: e);
    }
  }

  Future<void> setShowFrequency(bool value) async {
    if (_showFrequency == value) return;
    _showFrequency = value;
    AppLogger.i('[AppSettings] Afișare frecvență → $value');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShowFrequency, value);
    } catch (e) {
      AppLogger.e('[AppSettings] Nu am putut salva showFrequency', error: e);
    }
  }
}
