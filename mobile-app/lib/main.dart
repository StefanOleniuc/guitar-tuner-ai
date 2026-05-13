// ═══════════════════════════════════════════════════════════════
// Guitar Tuner AI - Aplicatie de tuner pentru chitara cu AI
// Autor: Oleniuc Stefan
// Universitatea Politehnica Timisoara - Ingineria Sistemelor
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'models/health_response.dart';
import 'services/api_service.dart';
import 'services/audio_service.dart';
import 'utils/app_logger.dart';
import 'utils/audio_utils.dart';

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
  final AudioService _audioService = AudioService();

  HealthResponse? _healthResponse;
  bool _isLoading = false;
  String? _errorMessage;

  bool _isRecording = false;
  int _bytesReceived = 0;
  int _sampleCount = 0;
  StreamSubscription<Uint8List>? _audioSubscription;

  double _currentVolume = 0.0;
  double _peakVolume = 0.0;

  @override
  void dispose() {
    _audioSubscription?.cancel();
    _audioService.dispose();
    super.dispose();
  }

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

  Future<void> _toggleRecording() async {
    if (!_isRecording) {
      bool permitted = await _audioService.hasPermission();
      if (!permitted) {
        permitted = await _audioService.requestPermission();
      }

      if (!permitted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aplicația are nevoie de acces la microfon pentru a detecta frecvența.',
            ),
          ),
        );
        return;
      }

      try {
        await _audioService.startRecording();
        if (!mounted) return;

        setState(() {
          _isRecording = true;
          _bytesReceived = 0;
          _sampleCount = 0;
        });

        _audioSubscription = _audioService.audioStream?.listen((chunk) {
          if (!mounted) return;
          final rms = AudioUtils.calculateRMS(chunk);
          final normalized = AudioUtils.rmsToNormalized(rms);
          setState(() {
            _bytesReceived += chunk.length;
            // PCM16 = 2 bytes per sample
            _sampleCount = _bytesReceived ~/ 2;
            _currentVolume = normalized;
            if (normalized > _peakVolume) _peakVolume = normalized;
          });
        });
      } catch (e) {
        AppLogger.e('❌ [HomeScreen] Eroare la pornirea capturii', error: e);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la captură: $e')),
        );
      }
    } else {
      try {
        await _audioService.stopRecording();
        await _audioSubscription?.cancel();
        _audioSubscription = null;
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _currentVolume = 0.0;
          _peakVolume = 0.0;
        });
      } catch (e) {
        AppLogger.e('❌ [HomeScreen] Eroare la oprirea capturii', error: e);
      }
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

              // ── Butoane test ──────────────────────────────────────
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

              // ── Secțiune captură audio ────────────────────────────
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _toggleRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isRecording ? Colors.red.shade700 : Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(
                    _isRecording ? '⏹️ Oprește captura' : '🎤 Începe captura audio',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              if (_isRecording) _buildRecordingCard(),
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

  Widget _buildRecordingCard() {
    final estimatedSeconds = _sampleCount / 16000;

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Înregistrare în curs...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Bytes primite: $_bytesReceived'),
            Text('Samples: $_sampleCount'),
            Text('Durată (estimată): ${estimatedSeconds.toStringAsFixed(2)}s'),
            const SizedBox(height: 16),
            _buildVolumeBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeBar() {
    final Color barColor;
    if (_currentVolume < 0.3) {
      barColor = Colors.green;
    } else if (_currentVolume < 0.7) {
      barColor = Colors.yellow;
    } else {
      barColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Volum:'),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 20,
            child: LinearProgressIndicator(
              value: _currentVolume,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Volum: ${(_currentVolume * 100).toStringAsFixed(1)}%'),
        Text('Peak: ${(_peakVolume * 100).toStringAsFixed(1)}%'),
      ],
    );
  }
}
