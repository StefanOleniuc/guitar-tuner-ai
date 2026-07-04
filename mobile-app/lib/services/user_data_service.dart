import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tuning_session.dart';
import '../utils/app_logger.dart';
import '../utils/constants.dart';
import 'app_settings.dart';
import 'auth_service.dart';

/// „Contul meu": sincronizare preferințe + istoric acordaje cu backend-ul.
///
/// Singleton `ChangeNotifier`. Ecranele ascultă pentru `historyTotal` și
/// `recentSessions` (numerele + lista din profil). Toată activitatea de
/// rețea e fail-safe: dacă backend-ul nu răspunde, app-ul rămâne pe
/// preferințele locale (shared_preferences) — nu blocăm niciun flow.
///
/// Convenții:
///   * `apply...` = aducem din backend → AppSettings local
///   * `push...`  = trimitem din AppSettings → backend
class UserDataService extends ChangeNotifier {
  UserDataService._();
  static final UserDataService instance = UserDataService._();

  int _historyTotal = 0;
  List<TuningSession> _recentSessions = const [];
  bool _historyLoading = false;
  // Ignorăm temporar push-urile când tocmai am apucat să aplicăm o
  // preferință venită din server (altfel apare un push redundant).
  bool _suppressNextPush = false;

  int get historyTotal => _historyTotal;
  List<TuningSession> get recentSessions => _recentSessions;
  bool get historyLoading => _historyLoading;

  String? get _token => AuthService.instance.token;

  /// La login (sau la restaurarea unei sesiuni valide): tragem preferințele
  /// + numărul total din istoric. Aplicarea peste `AppSettings` se face
  /// silent (fără să retrimitem același lucru înapoi la server).
  Future<void> onLoginSuccess() async {
    if (_token == null) return;
    AppLogger.i('[UserData] Login confirmat — sincronizez preferințe + istoric');
    await Future.wait([
      _fetchAndApplyPreferences(),
      refreshHistorySummary(),
    ]);
  }

  /// Logout — uităm tot ce e legat de cont și revenim la preferințele
  /// default (chitară + A4 440). Suprimăm push-ul pe AppSettings ca
  /// schimbarea să rămână strict locală — userul tocmai s-a delogat,
  /// nu mai sincronizăm nimic.
  void onLogout() {
    _historyTotal = 0;
    _recentSessions = const [];
    _suppressNextPush = true;
    AppSettings.instance.resetToDefaults();
    notifyListeners();
  }

  /// Trage preferințele și le aplică peste `AppSettings` (suprimă auto-push).
  Future<void> _fetchAndApplyPreferences() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.endpointUserPreferences}'),
            headers: _authHeaders(),
          )
          .timeout(ApiConstants.userDataTimeout);
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final instrument = j['instrument'] as String;
      final a4 = (j['a4'] as num).toDouble();
      // Backend trimite `leftHanded` (alias camelCase) sau `left_handed` din
      // versiuni mai vechi — acceptăm ambele.
      final leftHanded = (j['leftHanded'] ?? j['left_handed'] ?? false) as bool;
      _suppressNextPush = true;
      await AppSettings.instance.setInstrument(instrument);
      _suppressNextPush = true;
      await AppSettings.instance.setA4(a4);
      _suppressNextPush = true;
      await AppSettings.instance.setLeftHanded(leftHanded);
      AppLogger.i(
        '[UserData] Aplicat din server: $instrument @ A4=${a4.toStringAsFixed(0)}${leftHanded ? ' (stângaci)' : ''}',
      );
    } on TimeoutException {
      AppLogger.w('[UserData] Timeout la fetch preferințe');
    } on SocketException {
      AppLogger.w('[UserData] Fără rețea — preferințele rămân locale');
    } catch (e) {
      AppLogger.e('[UserData] Eroare la fetch preferințe', error: e);
    }
  }

  /// Apelat din `AppSettings` după ce userul schimbă instrument / A4 local.
  /// Trimitem schimbarea în backend doar dacă e logat și nu suntem chiar
  /// în mijlocul aplicării unei preferințe venite din server.
  Future<void> pushPreferencesFromSettings() async {
    if (_suppressNextPush) {
      _suppressNextPush = false;
      return;
    }
    if (_token == null) return; // user neautentificat → doar local
    try {
      final body = jsonEncode({
        'instrument': AppSettings.instance.instrumentId,
        'a4': AppSettings.instance.a4,
        'leftHanded': AppSettings.instance.leftHanded,
      });
      final res = await http
          .put(
            Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.endpointUserPreferences}'),
            headers: _authHeaders(json: true),
            body: body,
          )
          .timeout(ApiConstants.userDataTimeout);
      if (res.statusCode == 200) {
        AppLogger.i('[UserData] Preferințe sincronizate la server');
      } else {
        AppLogger.w('[UserData] Push preferințe → status ${res.statusCode}');
      }
    } catch (e) {
      // Nu deranjăm userul cu erori — următoarea schimbare le re-trimite.
      AppLogger.w('[UserData] Push preferințe eșuat: $e');
    }
  }

  /// Înregistrează o sesiune de acordaj. „Fire and forget" — dacă nu suntem
  /// logați sau rețeaua pică, nu deranjăm userul; pierdem doar acea sesiune
  /// din istoricul cloud (acordajul local nu e afectat).
  Future<void> recordSession({
    required String instrument,
    required String tuningName,
    required int stringsTuned,
    required int totalStrings,
    required double durationSeconds,
    required double a4,
  }) async {
    if (_token == null) return;
    try {
      final body = jsonEncode({
        'instrument': instrument,
        'tuning_name': tuningName,
        'strings_tuned': stringsTuned,
        'total_strings': totalStrings,
        'duration_seconds': durationSeconds,
        'a4': a4,
      });
      final res = await http
          .post(
            Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.endpointUserSessions}'),
            headers: _authHeaders(json: true),
            body: body,
          )
          .timeout(ApiConstants.userDataTimeout);
      if (res.statusCode == 200) {
        AppLogger.i('[UserData] Sesiune salvată: $instrument/$tuningName ($durationSeconds s)');
        // Reîmprospătare „lazy" a contoarelor afișate în profil/istoric.
        unawaited(refreshHistorySummary());
      } else {
        AppLogger.w('[UserData] Save sesiune → status ${res.statusCode}');
      }
    } catch (e) {
      AppLogger.w('[UserData] Save sesiune eșuat: $e');
    }
  }

  /// Reîmprospătează totalul + ultimele 5 sesiuni (pentru profil).
  /// Pentru ecranul de istoric folosim `fetchHistory(limit)` separat.
  Future<void> refreshHistorySummary() async {
    if (_token == null) return;
    _historyLoading = true;
    notifyListeners();
    try {
      final res = await http
          .get(
            Uri.parse(
                '${ApiConstants.apiBaseUrl}${ApiConstants.endpointUserSessions}?limit=5'),
            headers: _authHeaders(),
          )
          .timeout(ApiConstants.userDataTimeout);
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        _historyTotal = j['total'] as int;
        _recentSessions = (j['sessions'] as List)
            .map((e) => TuningSession.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      }
    } catch (e) {
      AppLogger.w('[UserData] Refresh istoric eșuat: $e');
    } finally {
      _historyLoading = false;
      notifyListeners();
    }
  }

  /// Întoarce ultimele `limit` sesiuni (full history screen).
  Future<List<TuningSession>> fetchHistory({int limit = 50}) async {
    if (_token == null) return const [];
    try {
      final res = await http
          .get(
            Uri.parse(
                '${ApiConstants.apiBaseUrl}${ApiConstants.endpointUserSessions}?limit=$limit'),
            headers: _authHeaders(),
          )
          .timeout(ApiConstants.userDataTimeout);
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        _historyTotal = j['total'] as int;
        final list = (j['sessions'] as List)
            .map((e) => TuningSession.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
        _recentSessions = list.take(5).toList(growable: false);
        notifyListeners();
        return list;
      }
    } catch (e) {
      AppLogger.w('[UserData] Fetch full istoric eșuat: $e');
    }
    return const [];
  }

  Map<String, String> _authHeaders({bool json = false}) {
    final h = <String, String>{'Authorization': 'Bearer $_token'};
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }
}
