import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  static const String _baseUrlDebug = 'http://192.168.1.134:8000';
  static const String _baseUrlProd = 'https://guitar-tuner-ai.onrender.com';

  static String get apiBaseUrl => kDebugMode ? _baseUrlDebug : _baseUrlProd;

  static const String endpointHealth = '/api/health';
  static const String endpointDetectPitch = '/api/detect-pitch';
  // CREPE AI Precision (verificare punctuală, ~1.5s sample)
  static const String endpointDetectPitchAI = '/api/pitch/detect';

  static const Duration apiTimeout = Duration(seconds: 5);
  // CREPE rulează pe TF, primul răspuns poate fi mai lent → mai mult timp
  static const Duration aiTimeout = Duration(seconds: 10);
}
