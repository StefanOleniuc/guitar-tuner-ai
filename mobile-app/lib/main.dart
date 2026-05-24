// ═══════════════════════════════════════════════════════════════
// Guitar Tuner AI - Aplicatie de tuner pentru chitara cu AI
// Autor: Oleniuc Stefan
// Universitatea Politehnica Timisoara - Ingineria Sistemelor
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'screens/main_shell.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'utils/app_logger.dart';
import 'utils/route_observer.dart';

Future<void> main() async {
  // Necesar înainte de orice plugin (shared_preferences) folosit în main.
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.i('🚀 [main] Aplicația Guitar Tuner AI pornește...');
  // Încărcăm preferințele + sesiunea de autentificare înainte de runApp
  // ca primul cadru să fie deja corect configurat.
  await AppSettings.instance.load();
  await AuthService.instance.loadSession();
  runApp(const GuitarTunerApp());
}

class GuitarTunerApp extends StatelessWidget {
  const GuitarTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    AppLogger.d('🎨 [GuitarTunerApp] Construire aplicație...');

    return MaterialApp(
      title: 'GTune AI - AI Guitar Tuner',
      debugShowCheckedModeBanner: false,
      // Observer global → shell-ul oprește microfonul/audio când se
      // deschide o rută peste el (Setări, Auth). Vezi `MainShell`.
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}
