import 'dart:math';
import 'dart:typed_data';

import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:pitch_detector_dart/exceptions/invalid_audio_buffer_exception.dart';

import '../models/pitch_result.dart';
import '../utils/app_logger.dart';

double _log2(double x) => log(x) / ln2;

class PitchService {
  static const int sampleRate = 16000;
  // 2048 sample = 128 ms @ 16 kHz: suficient pentru E2 (~10 perioade),
  // dar de 2x mai rapid decât 4096 → senzație real-time.
  static const int bufferSize = 2048;

  // Referința de acordaj A4 (Hz). Setată din AppSettings (calibrare).
  // Afectează toate conversiile notă↔frecvență din acest serviciu.
  double a4 = 440;

  // 0.0.7 folosește parametri numiți (audioSampleRate este double)
  final PitchDetector _pitchDetector = PitchDetector(
    audioSampleRate: sampleRate.toDouble(),
    bufferSize: bufferSize,
  );

  // PCM16 = 2 bytes/sample. Fereastră glisantă cu overlap: avansăm doar
  // cu un „hop" (jumătate de fereastră, ~64 ms) → analiză deasă, lină.
  Uint8List _buf = Uint8List(0);

  static const int _windowBytes = bufferSize * 2;
  static const int _hopBytes = bufferSize; // jumătate fereastră în bytes

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

    // Procesăm toate ferestrele disponibile (cu overlap), păstrând-o pe
    // cea mai recentă → fără acumulare de latență, mereu pe „acum".
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
      // Glisăm cu un hop (overlap = fereastră - hop)
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

  /// Conversie notă → frecvență. [a4] e referința de acordaj (440 Hz
  /// standard); apelanții interni pasează [this.a4] (calibrarea curentă).
  static double noteToFrequency(String note, {double a4 = 440}) {
    // Separă numele notei (literă + opțional #) de octavă (cifrele finale)
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
      // Selecție după distanța REALĂ (neclampată) — altfel note
      // îndepărtate ar fi egale la ±50 și s-ar confunda (ex. E2 vs E4).
      final raw = 1200 * _log2(freq / target);
      if (raw.abs() < bestAbsRaw) {
        bestAbsRaw = raw.abs();
        bestNote = n;
        bestRawCents = raw;
      }
    }

    // Afișăm cenții clampați la ±50 față de coarda aleasă
    final displayCents = bestRawCents.clamp(-50.0, 50.0);
    return (note: bestNote, cents: displayCents);
  }

  // La ciupit tare, YIN se agață des de armonica a 2-a (2x) sau semnalul
  // clipează → frecvență raportată greșit (de obicei un octav mai sus).
  // Cum știm notele acordajului, alegem factorul de octavă (x1, x½, x¼,
  // x2) care aduce frecvența cel mai aproape de o coardă. Nota corect
  // ciupită rămâne la x1 (cea mai mică distanță), deci E2/E4 NU se
  // confundă.
  /// [ref] = frecvența stabilă recentă (0 = necunoscută). Folosită pentru
  /// dezambiguizarea octavei: ex. un E4 care dă eroarea de octavă (~165Hz)
  /// poate plia la E2 SAU E4 (ambele la ~0¢) — alegem după continuitate.
  double foldToTuning(double freq, List<String> tuningNotes,
      {double ref = 0}) {
    if (freq <= 0) return freq;

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

    // Limitele plauzibile = min/max ale acordajului, ±1 octavă marjă.
    // Derivat din acordaj (nu hardcodat) → merge la fel pentru bas
    // (E1 ~41Hz) ca pentru vioară/mandolină (E5 ~659Hz).
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

    // Dacă frecvența brută (x1) e deja aproape de o coardă, NU pliem.
    final absAt1 = nearestAbs(freq);
    if (absAt1 <= 35) return freq;

    // Raw e departe de orice coardă → probabil eroare de octavă/armonică.
    const factors = [1.0, 0.5, 0.25, 2.0];
    double bestFactor = 1.0;
    double bestScore = double.infinity;

    for (final f in factors) {
      final cand = freq * f;
      if (cand < loBound || cand > hiBound) continue;
      final a = nearestAbs(cand);
      if (a > 45) continue; // nu cade pe nicio coardă → ignorăm

      double score = a;
      if (ref > 0) {
        // Continuitate: rămânem pe octava coardei pe care suntem deja
        score += (1200 * _log2(cand / ref)).abs() * 0.5;
      } else {
        // Fără context: penalizăm deplasarea de octavă; la egalitate
        // preferăm să URCĂM (eroarea YIN dominantă e octavă-prea-jos)
        score += _log2(f).abs() * 8;
        if (f < 1.0) score += 4;
      }
      if (score < bestScore) {
        bestScore = score;
        bestFactor = f;
      }
    }

    // Pliem doar dacă îmbunătățește clar față de x1.
    if (bestFactor != 1.0 && nearestAbs(freq * bestFactor) + 25 < absAt1) {
      return freq * bestFactor;
    }
    return freq;
  }
}
