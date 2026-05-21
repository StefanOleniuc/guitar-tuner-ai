// ═══════════════════════════════════════════════════════════════
// Guitar Tuner AI - Aplicatie de tuner pentru chitara cu AI
// Autor: Oleniuc Stefan
// Universitatea Politehnica Timisoara - Ingineria Sistemelor
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'screens/tuner_screen.dart';
import 'services/app_settings.dart';
import 'utils/app_logger.dart';

Future<void> main() async {
  // Necesar înainte de orice plugin (shared_preferences) folosit în main.
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.i('🚀 [main] Aplicația Guitar Tuner AI pornește...');
  // Încărcăm preferințele (instrument + calibrare A4) înainte de runApp
  // ca primul cadru să fie deja corect configurat.
  await AppSettings.instance.load();
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TunerScreen(),
    );
  }
}
