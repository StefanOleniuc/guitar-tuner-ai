// ═══════════════════════════════════════════════════════════════
// Guitar Tuner AI - Aplicatie de tuner pentru chitara cu AI
// Autor: Oleniuc Stefan
// Universitatea Politehnica Timisoara - Ingineria Sistemelor
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'models/health_response.dart';
import 'services/api_service.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  HealthResponse? _healthResponse;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _testBackend() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _healthResponse = null;
    });
    try {
      final result = await _apiService.checkHealth();
      if (!mounted) return;
      setState(() => _healthResponse = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.d('🎨 [HomeScreen] Construire ecran principal...');

    return Scaffold(
      appBar: AppBar(title: const Text('Guitar Tuner AI'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _testBackend,
                icon: const Icon(Icons.wifi),
                label: const Text('🌐 Test Backend Connection'),
              ),
              const SizedBox(height: 24),
              if (_isLoading) const CircularProgressIndicator(),
              if (_healthResponse != null) _buildResponseCard(),
              if (_errorMessage != null) _buildErrorBox(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponseCard() {
    final resp = _healthResponse!;
    final isOk = resp.status == 'ok';

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOk ? Icons.check_circle : Icons.error,
                  color: isOk ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  'Status: ${resp.status}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isOk ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Versiune: ${resp.version}'),
            Text('Mediu: ${resp.environment}'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBox() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(30),
        border: Border.all(color: Colors.red.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
