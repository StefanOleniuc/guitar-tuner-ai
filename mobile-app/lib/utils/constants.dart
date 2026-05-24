import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  static const String _baseUrlDebug = 'http://192.168.1.129:8000';
  static const String _baseUrlProd = 'https://guitar-tuner-ai.up.railway.app';

  static String get apiBaseUrl => kDebugMode ? _baseUrlDebug : _baseUrlProd;

  static const String endpointHealth = '/api/health';
  static const String endpointDetectPitch = '/api/detect-pitch';
  // CREPE AI Precision (verificare punctuală, ~1.5s sample)
  static const String endpointDetectPitchAI = '/api/pitch/detect';

  // Autentificare (email + parolă)
  static const String endpointRegister = '/api/auth/register';
  static const String endpointLogin = '/api/auth/login';
  static const String endpointMe = '/api/auth/me';
  static const String endpointResetPassword = '/api/auth/reset-password';
  static const String endpointResetConfirm = '/api/auth/reset-confirm';

  // „Contul meu": preferințe + istoric acordaje (necesită Bearer JWT)
  static const String endpointUserPreferences = '/api/user/preferences';
  static const String endpointUserSessions = '/api/user/tuning-sessions';

  static const Duration apiTimeout = Duration(seconds: 5);
  // CREPE rulează pe TF, primul răspuns poate fi mai lent → mai mult timp
  static const Duration aiTimeout = Duration(seconds: 10);
  static const Duration authTimeout = Duration(seconds: 8);
  // Sync „contul meu" — preferințe + istoric (rețea low-priority)
  static const Duration userDataTimeout = Duration(seconds: 8);
}
