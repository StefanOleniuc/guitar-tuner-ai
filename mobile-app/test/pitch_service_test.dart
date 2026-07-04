import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tuner_ai/services/pitch_service.dart';

void main() {
  group('PitchService.frequencyToNote', () {
    final svc = PitchService();

    test('A4 = 440 Hz → A4', () {
      expect(svc.frequencyToNote(440.0), equals('A4'));
    });

    test('E2 = 82.41 Hz → E2 (mi grav chitară)', () {
      expect(svc.frequencyToNote(82.41), equals('E2'));
    });

    test('E4 = 329.63 Hz → E4 (mi acut chitară)', () {
      expect(svc.frequencyToNote(329.63), equals('E4'));
    });

    test('C4 = 261.63 Hz → C4 (do central pian)', () {
      expect(svc.frequencyToNote(261.63), equals('C4'));
    });

    test('frecvență nulă/negativă → null', () {
      expect(svc.frequencyToNote(0), isNull);
      expect(svc.frequencyToNote(-100), isNull);
    });
  });

  group('PitchService.calculateCents', () {
    final svc = PitchService();

    test('frecvență egală cu ținta → 0 cents', () {
      expect(svc.calculateCents(440, 440), closeTo(0, 0.01));
    });

    test('o octavă mai sus → +1200 saturat la +50', () {
      expect(svc.calculateCents(880, 440), equals(50));
    });

    test('o octavă mai jos → −1200 saturat la −50', () {
      expect(svc.calculateCents(220, 440), equals(-50));
    });

    test('+1 semiton (442.27 ÷ 440 = +9 cents aprox)', () {
      // Un semiton are 100 cents; ~9 cents sub un semiton.
      expect(svc.calculateCents(442.27, 440), closeTo(8.92, 0.5));
    });

    test('rezultat saturat la ±50 cents', () {
      expect(svc.calculateCents(500, 440).abs() <= 50, isTrue);
      expect(svc.calculateCents(380, 440).abs() <= 50, isTrue);
    });
  });

  group('PitchService.noteToFrequency (static)', () {
    test('A4 → 440 Hz', () {
      expect(PitchService.noteToFrequency('A4'), closeTo(440.0, 0.01));
    });

    test('E2 → 82.41 Hz', () {
      expect(PitchService.noteToFrequency('E2'), closeTo(82.41, 0.01));
    });

    test('A4 cu calibrare 442 Hz', () {
      expect(PitchService.noteToFrequency('A4', a4: 442), closeTo(442.0, 0.01));
    });

    test('formatul invalid → 0', () {
      expect(PitchService.noteToFrequency('XYZ'), equals(0));
    });
  });

  group('PitchService.nearestNoteInTuning', () {
    final svc = PitchService();
    const standardE = ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];

    test('E2 exact → cea mai apropiată este E2', () {
      final r = svc.nearestNoteInTuning(82.41, standardE);
      expect(r.note, equals('E2'));
      expect(r.cents.abs() < 1, isTrue);
    });

    test('441 Hz (puțin peste E4=329.63) → totuși E4 dacă restul departe', () {
      final r = svc.nearestNoteInTuning(330.0, standardE);
      expect(r.note, equals('E4'));
    });
  });

  group('PitchService.foldToTuning (corecția erorilor de octavă)', () {
    final svc = PitchService();
    const standardE = ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];

    test('subarmonică 2·E2 (164.82 Hz) → pliată înapoi la E2 (~82.41)', () {
      // YIN raportează armonica a 2-a a corzii E2; cu referința recentă
      // de 82.41 Hz, folding-ul o readuce la fundamentală.
      final f = svc.foldToTuning(164.82, standardE, ref: 82.41);
      expect(f, closeTo(82.41, 1.0));
    });

    test('jumătate de A2 (55 Hz = A1) → ridicată la A2 (110 Hz)', () {
      final f = svc.foldToTuning(55.0, standardE, ref: 110.0);
      expect(f, closeTo(110.0, 1.0));
    });

    test('frecvență deja pe o coardă → rămâne neschimbată', () {
      final f = svc.foldToTuning(82.41, standardE, ref: 82.41);
      expect(f, closeTo(82.41, 0.01));
    });

    test('fără referință de continuitate → nu se pliază', () {
      // ref = 0 (implicit): fără context nu riscăm o octavă greșită.
      final f = svc.foldToTuning(164.82, standardE);
      expect(f, closeTo(164.82, 0.01));
    });
  });

  group('PitchService.isPlausibleForTuning (poartă de plauzibilitate)', () {
    final svc = PitchService();
    const standardE = ['E2', 'A2', 'D3', 'G3', 'B3', 'E4'];

    test('frecvență pe o coardă → plauzibilă', () {
      expect(svc.isPlausibleForTuning(82.41, standardE), isTrue);
    });

    test('armonică neidentificată (1469 Hz, >2000¢ de orice coardă) → respinsă', () {
      expect(svc.isPlausibleForTuning(1469.0, standardE), isFalse);
    });

    test('pragul maxCents controlează acceptarea (85 Hz ≈ 54¢ față de E2)', () {
      expect(svc.isPlausibleForTuning(85.0, standardE, maxCents: 75), isTrue);
      expect(svc.isPlausibleForTuning(85.0, standardE, maxCents: 40), isFalse);
    });
  });
}
