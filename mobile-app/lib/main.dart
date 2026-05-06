// ═══════════════════════════════════════════════════════════════
// Guitar Tuner AI - Aplicație de tuner pentru chitară cu AI
// Autor: Oleniuc Ștefan
// Universitatea Politehnica Timișoara - Ingineria Sistemelor
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

// Logger global — folosit în toată aplicația
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0, // nu afișa stack trace pentru fiecare log
    errorMethodCount: 5, // dar pentru erori, afișează 5 niveluri
    lineLength: 80,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);

void main() {
  logger.i('🚀 [main] Aplicația Guitar Tuner AI pornește...');
  runApp(const GuitarTunerApp());
}

class GuitarTunerApp extends StatelessWidget {
  const GuitarTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    logger.d('🎨 [GuitarTunerApp] Construire aplicație...');

    return MaterialApp(
      title: 'Guitar Tuner AI',
      debugShowCheckedModeBanner: false, // ascunde banner-ul "DEBUG"
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark, // tema dark default
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
    logger.d('🏠 [HomeScreen] Construire ecran principal...');

    return Scaffold(
      appBar: AppBar(title: const Text('Guitar Tuner AI STEFAN'), centerTitle: true),
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
                logger.i('👆 [HomeScreen] Buton test apăsat!');
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
