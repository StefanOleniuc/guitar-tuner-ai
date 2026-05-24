import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';
import '../utils/app_logger.dart';
import '../utils/constants.dart';
import '../widgets/app_dialog.dart';
import 'user_data_service.dart';

/// Cere confirmare userului înainte de a-l deconecta. Reutilizat din mai
/// multe ecrane (Setări, Cont) — un singur popup, comportament uniform.
Future<void> confirmAndLogout(BuildContext context) async {
  HapticFeedback.selectionClick();
  final ok = await showAppConfirm(
    context,
    icon: Icons.logout_rounded,
    title: 'Te deconectezi?',
    message:
        'Pierzi accesul rapid la istoricul și preferințele sincronizate. '
        'Le poți reaccesa oricând conectându-te din nou.',
    confirmLabel: 'Deconectează-te',
    cancelLabel: 'Rămân conectat',
  );
  if (!ok) return;
  await AuthService.instance.logout();
}

/// Serviciul de autentificare — email + parolă, token JWT.
///
/// Singleton `ChangeNotifier`: ecranele ascultă starea de login.
/// Token-ul + datele contului sunt persistate cu `shared_preferences`,
/// deci sesiunea supraviețuiește repornirii aplicației.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String _kToken = 'auth.token';
  static const String _kUser = 'auth.user';

  String? _token;
  AuthUser? _user;

  bool get isAuthenticated => _user != null;
  AuthUser? get user => _user;
  String? get token => _token;

  /// Încarcă sesiunea salvată. De apelat la pornire (în `main`).
  /// Afișează imediat contul din cache, apoi validează token-ul cu
  /// serverul în fundal (dacă e invalid → delogare).
  Future<void> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_kToken);
      final cached = prefs.getString(_kUser);
      if (_token == null || cached == null) return;
      _user = AuthUser.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      AppLogger.i('🔐 [Auth] Sesiune restaurată: ${_user!.email}');
      notifyListeners();
      // Validare în fundal — nu blocăm pornirea.
      unawaited(_validateToken());
    } catch (e) {
      AppLogger.e('❌ [Auth] Eroare la încărcarea sesiunii', error: e);
    }
  }

  Future<void> _validateToken() async {
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.endpointMe}'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(ApiConstants.authTimeout);
      if (res.statusCode == 200) {
        _user = AuthUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        await _persist();
        notifyListeners();
        // Token încă valid → tragem preferințele + istoricul din cloud.
        unawaited(UserDataService.instance.onLoginSuccess());
      } else if (res.statusCode == 401) {
        AppLogger.w('🔶 [Auth] Token expirat — delogare');
        await logout();
      }
    } catch (_) {
      // Fără rețea → păstrăm sesiunea din cache, revalidăm data viitoare.
    }
  }

  /// Înregistrare cont nou. Întoarce `null` la succes sau un mesaj de
  /// eroare prietenos.
  Future<String?> register(String email, String password, String? displayName) {
    return _authCall(ApiConstants.endpointRegister, {
      'email': email,
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty)
        'displayName': displayName.trim(),
    });
  }

  /// Autentificare. Întoarce `null` la succes sau un mesaj de eroare.
  Future<String?> login(String email, String password) {
    return _authCall(ApiConstants.endpointLogin, {
      'email': email,
      'password': password,
    });
  }

  Future<String?> _authCall(String endpoint, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConstants.apiBaseUrl}$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(ApiConstants.authTimeout);

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        _token = json['token'] as String;
        _user = AuthUser.fromJson(json['user'] as Map<String, dynamic>);
        await _persist();
        AppLogger.i('🔐 [Auth] Autentificat: ${_user!.email}');
        notifyListeners();
        // Așteptăm sync-ul preferințelor + istoricului ÎNAINTE să închidem
        // ecranul de auth — așa userul vede deja instrumentul + A4 lui
        // când ajunge pe Tuner, fără un cadru de „flicker la default".
        await UserDataService.instance.onLoginSuccess();
        return null;
      }
      // Backend-ul întoarce mesaje prietenoase în `detail`.
      return (json['detail'] as String?) ??
          'A apărut o eroare. Încearcă din nou.';
    } on TimeoutException {
      return 'Serverul nu răspunde. Verifică conexiunea la internet.';
    } on SocketException {
      return 'Fără conexiune la internet. Încearcă din nou.';
    } catch (e) {
      AppLogger.e('❌ [Auth] Eroare neașteptată', error: e);
      return 'A apărut o eroare neașteptată.';
    }
  }

  /// Cerere de resetare a parolei (pasul 1 — trimite cod OTP pe email).
  /// Întoаrce `null` la succes sau un mesaj de eroare la problemă de rețea.
  Future<String?> requestPasswordReset(String email) async {
    try {
      final res = await http
          .post(
            Uri.parse(
              '${ApiConstants.apiBaseUrl}${ApiConstants.endpointResetPassword}',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(ApiConstants.authTimeout);
      if (res.statusCode == 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return (json['detail'] as String?) ?? 'A apărut o eroare.';
    } catch (_) {
      return 'Nu mă pot conecta la server. Încearcă mai târziu.';
    }
  }

  /// Confirmare cod OTP + parolă nouă (pasul 2).
  /// Întoаrce `null` la succes sau un mesaj de eroare.
  Future<String?> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse(
              '${ApiConstants.apiBaseUrl}${ApiConstants.endpointResetConfirm}',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'code': code,
              'new_password': newPassword,
            }),
          )
          .timeout(ApiConstants.authTimeout);
      if (res.statusCode == 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return (json['detail'] as String?) ?? 'Cod invalid sau expirat.';
    } catch (_) {
      return 'Nu mă pot conecta la server. Încearcă mai târziu.';
    }
  }

  /// Actualizează numele afișat al userului. Întoarce `null` la succes
  /// sau un mesaj de eroare prietenos.
  Future<String?> updateDisplayName(String displayName) async {
    if (_token == null) return 'Trebuie să fii autentificat.';
    final trimmed = displayName.trim();
    try {
      final res = await http
          .put(
            Uri.parse('${ApiConstants.apiBaseUrl}${ApiConstants.endpointMe}'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'displayName': trimmed.isEmpty ? null : trimmed}),
          )
          .timeout(ApiConstants.authTimeout);
      if (res.statusCode == 200) {
        _user = AuthUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        await _persist();
        notifyListeners();
        return null;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return (json['detail'] as String?) ?? 'Nu am putut salva numele.';
    } on TimeoutException {
      return 'Serverul nu răspunde. Încearcă din nou.';
    } on SocketException {
      return 'Fără conexiune la internet.';
    } catch (e) {
      AppLogger.e('❌ [Auth] Eroare la update profil', error: e);
      return 'A apărut o eroare neașteptată.';
    }
  }

  Future<void> logout() async {
    AppLogger.i('🔐 [Auth] Delogare');
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
    notifyListeners();
    UserDataService.instance.onLogout();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString(_kToken, _token!);
    if (_user != null) {
      await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
    }
  }
}
