import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../utils/app_logger.dart';
import 'pitch_service.dart';

/// Sintetizează și redă **note de referință** pentru fiecare coardă.
///
/// Folosim sinteza aditivă cu 3 armonici (1×, 2×, 3× freq) și o anvelopă
/// atac-decay blândă — sună „cald" și natural, nu o sirenă. Nu e identic
/// cu o coardă reală (ar trebui sample-uri pre-înregistrate per instrument,
/// MB-uri de assets), dar e foarte aproape pentru ureche.
///
/// WAV-urile sunt cache-uite pe combinația notă+A4: o notă cântată de
/// două ori NU regenerează datele audio.
class NoteAudio {
  NoteAudio._();
  static final NoteAudio instance = NoteAudio._();

  final AudioPlayer _player = AudioPlayer();
  final Map<String, Uint8List> _cache = {};

  /// Generează (dacă e nevoie) și redă nota dată. Întrerupe sunetul anterior
  /// — userul nu vrea două note suprapuse când dă tap rapid.
  Future<void> play(String fullNote, {double a4 = 440.0}) async {
    try {
      final freq = PitchService.noteToFrequency(fullNote, a4: a4);
      final key = '${fullNote}_${a4.toStringAsFixed(1)}';
      final wav = _cache.putIfAbsent(key, () => _noteWav(freq));
      await _player.stop();
      await _player.play(BytesSource(wav));
    } catch (e) {
      AppLogger.w('🔶 [NoteAudio] Redare eșuată ($fullNote): $e');
    }
  }

  /// Eliberează resursele. De apelat la închiderea aplicației — momentan
  /// nu o facem explicit (singleton-ul trăiește cât app-ul).
  Future<void> dispose() async {
    _cache.clear();
    await _player.dispose();
  }

  /// Sintetizează ~1.5s de notă cu timbru tipic de coardă plucată:
  ///   * 5 armonici (1× la 5× freq), fiecare cu propria rată de decay —
  ///     armonicile înalte fade mai repede, fundamentala susține. Așa
  ///     se aude ca o coardă, nu ca o sirenă.
  ///   * burst scurt de zgomot la atac (~4ms) → senzația de „pluck".
  ///   * atac scurt (6ms ramp) + decay exponențial per armonică.
  static Uint8List _noteWav(double freq) {
    const sampleRate = 44100;
    const durationMs = 1600;
    const attackMs = 6;
    final n = sampleRate * durationMs ~/ 1000;
    final attackSamples = sampleRate * attackMs ~/ 1000;
    final samples = Int16List(n);

    // [amplitudine_inițială, rata_decay] per armonică (1..5).
    // Armonicile înalte fade mai rapid — pluck-ul „strălucește" la
    // început, apoi se așază pe fundamentală caldă.
    const harmonics = <List<double>>[
      [1.00, 1.6], // fundamental — sustain principal
      [0.55, 2.8], // 2nd — warmth
      [0.32, 4.5], // 3rd
      [0.18, 6.5], // 4th
      [0.10, 9.5], // 5th — body / bite
    ];
    // Normalizare: suma amplitudinilor la t=0 = ~2.15 → împărțim ca să
    // nu clip-uim peak-ul inițial.
    var ampSum = 0.0;
    for (final h in harmonics) {
      ampSum += h[0];
    }
    final norm = 1.0 / ampSum;
    final rng = Random(42);

    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      final attack = i < attackSamples ? i / attackSamples : 1.0;
      double s = 0.0;
      for (int h = 0; h < harmonics.length; h++) {
        final amp = harmonics[h][0];
        final dec = harmonics[h][1];
        s += amp * exp(-dec * t) * sin(2 * pi * freq * (h + 1) * t);
      }
      s = s * norm * attack * 0.78;
      // Pluck noise — zgomot scurt la atac care imită degetul atingând
      // coarda. Doar primele ~4ms, scade liniar.
      if (t < 0.004) {
        final noise = (rng.nextDouble() * 2 - 1) * 0.12 * (1 - t / 0.004);
        s += noise;
      }
      samples[i] = (s * 32767).round().clamp(-32768, 32767);
    }
    return _pcmToWav(samples, sampleRate);
  }

  static Uint8List _pcmToWav(Int16List samples, int sampleRate) {
    final pcm = samples.buffer.asUint8List();
    final dataSize = pcm.length;
    final out = BytesBuilder();
    void str(String s) => out.add(s.codeUnits);
    void u32(int v) => out.add([
          v & 0xff,
          (v >> 8) & 0xff,
          (v >> 16) & 0xff,
          (v >> 24) & 0xff,
        ]);
    void u16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);

    str('RIFF');
    u32(36 + dataSize);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    str('data');
    u32(dataSize);
    out.add(pcm);
    return out.toBytes();
  }
}
