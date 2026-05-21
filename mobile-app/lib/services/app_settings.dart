import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/instrument.dart';
import '../utils/app_logger.dart';

/// Preferințele aplicației, persistate cu `shared_preferences`.
///
/// Singleton `ChangeNotifier` — ecranele se abonează (`addListener`) și
/// se reconstruiesc când utilizatorul schimbă instrumentul sau A4-ul.
/// Se încarcă o singură dată la pornire, în `main()`, înainte de runApp.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // Calibrare A4: 440 Hz e standardul ISO 16. Gama 415-466 acoperă
  // tot ce se folosește în practică (baroc ~415 → orchestre ~466).
  static const double defaultA4 = 440;
  static const double minA4 = 415;
  static const double maxA4 = 466;

  static const String _kInstrument = 'settings.instrumentId';
  static const String _kA4 = 'settings.a4';
  static const String _kShowFrequency = 'settings.showFrequency';

  String _instrumentId = Instrument.guitar.id;
  double _a4 = defaultA4;
  bool _showFrequency = true;

  String get instrumentId => _instrumentId;
  Instrument get instrument => Instrument.byId(_instrumentId);
  double get a4 => _a4;

  /// Dacă afișăm frecvența (Hz) sub notă pe ecranul tunerului.
  bool get showFrequency => _showFrequency;

  /// Încărcare din storage. De apelat o singură dată, în `main()`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _instrumentId = prefs.getString(_kInstrument) ?? Instrument.guitar.id;
      _a4 = (prefs.getDouble(_kA4) ?? defaultA4).clamp(minA4, maxA4);
      _showFrequency = prefs.getBool(_kShowFrequency) ?? true;
      AppLogger.i('⚙️ [AppSettings] Încărcat: instrument=$_instrumentId, '
          'A4=${_a4.toStringAsFixed(0)} Hz, freq=$_showFrequency');
    } catch (e) {
      AppLogger.e('❌ [AppSettings] Eroare la încărcare — folosesc default',
          error: e);
    }
    notifyListeners();
  }

  Future<void> setInstrument(String id) async {
    if (_instrumentId == id) return;
    _instrumentId = id;
    AppLogger.i('⚙️ [AppSettings] Instrument → $id');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kInstrument, id);
    } catch (e) {
      AppLogger.e('❌ [AppSettings] Nu am putut salva instrumentul', error: e);
    }
  }

  Future<void> setA4(double value) async {
    final v = value.clamp(minA4, maxA4).toDouble();
    if (v == _a4) return;
    _a4 = v;
    AppLogger.i('⚙️ [AppSettings] A4 → ${v.toStringAsFixed(0)} Hz');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kA4, v);
    } catch (e) {
      AppLogger.e('❌ [AppSettings] Nu am putut salva A4', error: e);
    }
  }

  void resetA4() => setA4(defaultA4);

  Future<void> setShowFrequency(bool value) async {
    if (_showFrequency == value) return;
    _showFrequency = value;
    AppLogger.i('⚙️ [AppSettings] Afișare frecvență → $value');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShowFrequency, value);
    } catch (e) {
      AppLogger.e('❌ [AppSettings] Nu am putut salva showFrequency', error: e);
    }
  }
}
