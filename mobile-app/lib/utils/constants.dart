import 'package:flutter/foundation.dart';

class ApiConstants {
  ApiConstants._();

  static const String _baseUrlDebug = 'http://192.168.0.234:8000';
  static const String _baseUrlProd = 'https://guitar-tuner-ai.onrender.com';

  static String get apiBaseUrl => kDebugMode ? _baseUrlDebug : _baseUrlProd;

  static const String endpointHealth = '/api/health';
  static const String endpointDetectPitch = '/api/detect-pitch';

  static const Duration apiTimeout = Duration(seconds: 5);
}
