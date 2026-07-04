import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../utils/app_logger.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  Stream<Uint8List>? _audioStream;
  bool _isRecording = false;

  Stream<Uint8List>? get audioStream => _audioStream;
  bool get isRecording => _isRecording;

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    AppLogger.i('[AudioService] Permission status: $status');
    return status.isGranted;
  }

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    AppLogger.i('[AudioService] Permission request result: $status');
    return status.isGranted;
  }

  /// Deschide setările de sistem — singura cale după un refuz permanent.
  Future<void> openSystemSettings() async {
    AppLogger.i('[AudioService] Deschid setările de sistem');
    await openAppSettings();
  }

  Future<void> startRecording() async {
    if (!await hasPermission()) {
      throw Exception('Permisiunea pentru microfon nu a fost acordată');
    }

    try {
      AppLogger.i('[AudioService] Pornire captură audio...');

      // 16kHz mono PCM16 — format optim pentru pitch detection.
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );

      // Broadcast: permite multipli ascultători (tuner + captură AI).
      final source = await _recorder.startStream(config);
      _audioStream = source.asBroadcastStream();
      _isRecording = true;

      AppLogger.i('[AudioService] Captură pornită — 16kHz, mono, PCM16');
    } catch (e) {
      AppLogger.e('[AudioService] Eroare la pornirea capturii', error: e);
      _isRecording = false;
      rethrow;
    }
  }

  Future<void> stopRecording() async {
    try {
      AppLogger.i('[AudioService] Oprire captură audio...');
      await _recorder.stop();
      _audioStream = null;
      _isRecording = false;
      AppLogger.i('[AudioService] Captură oprită');
    } catch (e) {
      AppLogger.e('[AudioService] Eroare la oprirea capturii', error: e);
      _isRecording = false;
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
    AppLogger.d('[AudioService] Resurse AudioRecorder eliberate');
  }
}
