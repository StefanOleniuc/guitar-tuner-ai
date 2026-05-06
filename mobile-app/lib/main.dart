// ═══════════════════════════════════════════════════════════════
// Guitar Tuner AI - Aplicatie de tuner pentru chitara cu AI
// Autor: Oleniuc Stefan
// Universitatea Politehnica Timisoara - Ingineria Sistemelor
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'utils/app_logger.dart';

void main() {
  AppLogger.i('🚀 [main] Aplicația Guitar Tuner AI pornește...');
  runApp(const GuitarTunerApp());
}

class GuitarTunerApp extends StatelessWidget {
  const GuitarTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    AppLogger.d('🎨 [GuitarTunerApp] Construire aplicație...');

    return MaterialApp(
      title: 'Guitar Tuner AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppLogger.d('🏠 [HomeScreen] Construire ecran principal...');

    return Scaffold(
      appBar: AppBar(title: const Text('Guitar Tuner AI'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_note, size: 100, color: Colors.deepPurple),
            const SizedBox(height: 24),
            Text(
              'Guitar Tuner AI',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Aplicația va fi construită aici 🎸',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                AppLogger.i('👆 [HomeScreen] Buton test apăsat!');
                AppLogger.d('🔍 [HomeScreen] Debug message');
                AppLogger.w('🔶 [HomeScreen] Test warning');
              },
              icon: const Icon(Icons.touch_app),
              label: const Text('Test Logger'),
            ),
          ],
        ),
      ),
    );
  }
}
