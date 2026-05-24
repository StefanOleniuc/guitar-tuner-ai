import 'dart:math';
import 'dart:typed_data';

import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:pitch_detector_dart/exceptions/invalid_audio_buffer_exception.dart';

import '../models/pitch_result.dart';
import '../utils/app_logger.dart';

double _log2(double x) => log(x) / ln2;

class PitchService {
  static const int sampleRate = 16000;
  // 128ms @ 16kHz — suficient pentru E2, răspuns real-time.
  static const int bufferSize = 2048;

  // Referința de acordaj A4 (Hz), setată din setări.
  double a4 = 440;

  final PitchDetector _pitchDetector = PitchDetector(
    audioSampleRate: sampleRate.toDouble(),
    bufferSize: bufferSize,
  );

  // Fereastră glisantă PCM16, hop = jumătate din fereastră (~64ms).
  Uint8List _buf = Uint8List(0);

  static const int _windowBytes = bufferSize * 2;
  static const int _hopBytes = bufferSize;

  static const List<String> _noteNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  Future<PitchResult> analyze(Uint8List chunk) async {
    final merged = Uint8List(_buf.length + chunk.length)
      ..setRange(0, _buf.length, _buf)
      ..setRange(_buf.length, _buf.length + chunk.length, chunk);
    _buf = merged;

    if (_buf.length < _windowBytes) return PitchResult.empty();

    PitchResult result = PitchResult.empty();

    // Procesăm ferestrele cu overlap, păstrând cea mai recentă.
    while (_buf.length >= _windowBytes) {
      final window = Uint8List.sublistView(_buf, 0, _windowBytes);
      try {
        final r = await _pitchDetector.getPitchFromIntBuffer(window);
        result = PitchResult(
          frequency: r.pitch,
          pitched: r.pitched,
          probability: r.probability,
        );
        if (r.pitched) {
          AppLogger.d(
            '🎸 [PitchService] raw=${r.pitch.toStringAsFixed(1)}Hz '
            'p=${r.probability.toStringAsFixed(2)}',
          );
        }
      } on InvalidAudioBufferException catch (e) {
        AppLogger.e('❌ [PitchService] Buffer audio invalid', error: e);
        result = PitchResult.empty();
      }
      // Glisăm cu un hop.
      _buf = Uint8List.sublistView(_buf, _hopBytes);
    }

    return result;
  }

  String? frequencyToNote(double freq) {
    if (freq <= 0) return null;
    final noteIndex = (12 * _log2(freq / a4)).round() + 69;
    final octave = (noteIndex ~/ 12) - 1;
    return '${_noteNames[noteIndex % 12]}$octave';
  }

  double calculateCents(double detected, double target) {
    if (target <= 0 || detected <= 0) return 0;
    return (1200 * _log2(detected / target)).clamp(-50.0, 50.0);
  }

  static double noteToFrequency(String note, {double a4 = 440}) {
    final match = RegExp(r'^([A-G]#?)(-?\d+)$').firstMatch(note);
    if (match == null) return 0;
    final nameIndex = _noteNames.indexOf(match.group(1)!);
    final octave = int.parse(match.group(2)!);
    final midi = nameIndex + (octave + 1) * 12;
    return a4 * pow(2, (midi - 69) / 12);
  }

  ({String note, double cents}) nearestNoteInTuning(
    double freq,
    List<String> tuningNotes,
  ) {
    if (freq <= 0) return (note: '', cents: 0);

    String bestNote = '';
    double bestRawCents = 0;
    double bestAbsRaw = double.infinity;

    for (final n in tuningNotes) {
      final target = noteToFrequency(n, a4: a4);
      if (target <= 0) continue;
      // Distanță neclampată — evită confuzia E2 vs E4 la ±50¢.
      final raw = 1200 * _log2(freq / target);
      if (raw.abs() < bestAbsRaw) {
        bestAbsRaw = raw.abs();
        bestNote = n;
        bestRawCents = raw;
      }
    }

    // Afișăm cenții clampați la ±50¢.
    final displayCents = bestRawCents.clamp(-50.0, 50.0);
    return (note: bestNote, cents: displayCents);
  }

  // Corectează erorile de octavă YIN (armonice). [ref] = frecvența recentă
  // pentru dezambiguizarea octavei prin continuitate.
  double foldToTuning(double freq, List<String> tuningNotes, {double ref = 0}) {
    if (freq <= 0) return freq;

    // Fără referință de continuitate nu pliem — risc de octavă greșită.
    if (ref <= 0) return freq;

    double nearestAbs(double f) {
      double best = double.infinity;
      for (final n in tuningNotes) {
        final target = noteToFrequency(n, a4: a4);
        if (target <= 0) continue;
        final c = (1200 * _log2(f / target)).abs();
        if (c < best) best = c;
      }
      return best;
    }

    // Limite plauzibile derivate din acordaj (±1 octavă marjă).
    double loTarget = double.infinity;
    double hiTarget = 0;
    for (final n in tuningNotes) {
      final t = noteToFrequency(n, a4: a4);
      if (t <= 0) continue;
      if (t < loTarget) loTarget = t;
      if (t > hiTarget) hiTarget = t;
    }
    if (hiTarget == 0) return freq; // acordaj invalid
    final loBound = loTarget * 0.5;
    final hiBound = hiTarget * 2.0;

    final absAt1 = nearestAbs(freq);
    if (absAt1 <= 35) return freq;

    // Departe de orice coardă → probabil eroare de octavă/armonică.
    // Acoperim subharmonice până la /16 (corzi groase: ex. 36Hz ≈ D3/4)
    // și superharmonice până la x4 (YIN sare ocazional pe H2-H4 la corzi
    // subțiri). Includem și factori 3 / 1/3 pentru cvinta perfectă (a 3-a
    // armonică). Penalizarea de continuitate (`ref`) îi taie pe cei improbabili.
    const factors = [1.0, 0.5, 2.0, 0.25, 4.0, 0.125, 0.0625, 1.0 / 3.0, 3.0];
    double bestFactor = 1.0;
    double bestScore = double.infinity;

    for (final f in factors) {
      final cand = freq * f;
      if (cand < loBound || cand > hiBound) continue;
      final a = nearestAbs(cand);
      if (a > 45) continue; // nu cade pe nicio coardă → ignorăm

      double score = a;
      if (ref > 0) {
        // Penalizăm distanța față de referința recentă (continuitate).
        score += (1200 * _log2(cand / ref)).abs() * 0.5;
      } else {
        score += _log2(f).abs() * 8;
        if (f < 1.0) score += 4;
      }
      if (score < bestScore) {
        bestScore = score;
        bestFactor = f;
      }
    }

    // Pliem doar dacă îmbunătățește față de x1.
    if (bestFactor != 1.0 && nearestAbs(freq * bestFactor) + 25 < absAt1) {
      return freq * bestFactor;
    }
    return freq;
  }

  /// Returnează `true` dacă [freq] cade la cel mult [maxCents] (absolut)
  /// de cea mai apropiată coardă din [tuningNotes]. Folosit ca "plausibility
  /// gate" — frecvențele YIN care nici după `foldToTuning` nu se apropie de
  /// o coardă reală sunt zgomot/armonice neidentificate și ar trebui ignorate
  /// (altfel ajung clampate la ±50¢ și mint utilizatorul).
  bool isPlausibleForTuning(
    double freq,
    List<String> tuningNotes, {
    double maxCents = 75,
  }) {
    if (freq <= 0) return false;
    double best = double.infinity;
    for (final n in tuningNotes) {
      final target = noteToFrequency(n, a4: a4);
      if (target <= 0) continue;
      final c = (1200 * _log2(freq / target)).abs();
      if (c < best) best = c;
    }
    return best <= maxCents;
  }
}
