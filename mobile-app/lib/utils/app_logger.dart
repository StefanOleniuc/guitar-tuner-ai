// ═══════════════════════════════════════════════════════════════
// AppLogger - Logging in consola pentru dezvoltare
//
// Format output: [APP_LOG] [LEVEL] HH:mm:ss.SSS - mesaj
// Toate liniile contin [APP_LOG] pentru filtrare usoara.
//
// Folosinta:
//   AppLogger.i('mesaj info');
//   AppLogger.d('mesaj debug');
//   AppLogger.w('mesaj warning');
//   AppLogger.e('eroare', error: e, stackTrace: st);
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

class AppLogger {
  static const String _tag = '[APP_LOG]';

  static String _now() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Debug - detalii tehnice
  static void d(dynamic message) {
    if (kDebugMode) {
      debugPrint('$_tag [D] ${_now()} - $message');
    }
  }

  /// Info - evenimente normale
  static void i(dynamic message) {
    if (kDebugMode) {
      debugPrint('$_tag [I] ${_now()} - $message');
    }
  }

  /// Warning - ceva neobisnuit
  static void w(dynamic message) {
    if (kDebugMode) {
      debugPrint('$_tag [W] ${_now()} - $message');
    }
  }

  /// Error - probleme reale
  static void e(dynamic message, {Object? error, StackTrace? stackTrace}) {
    if (kDebugMode) {
      debugPrint('$_tag [E] ${_now()} - $message');
      if (error != null) {
        debugPrint('$_tag [E] ${_now()} - Error details: $error');
      }
      if (stackTrace != null) {
        debugPrint('$_tag [E] ${_now()} - Stack trace:\n$stackTrace');
      }
    }
  }
}
