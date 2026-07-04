import 'tuning.dart';

/// Un instrument cu corzi și acordajele lui disponibile.
///
/// Instrumentul activ se alege din Setări; acordajul concret (când
/// instrumentul are mai multe) se alege din selectorul de sus al
/// tunerului. Detecția de pitch (YIN + CREPE) e identică indiferent de
/// instrument — se schimbă doar setul de note-țintă.
class Instrument {
  const Instrument({
    required this.id,
    required this.name,
    required this.emoji,
    required this.tunings,
  });

  /// Identificator stabil — persistat în shared_preferences.
  final String id;

  /// Nume afișat (RO).
  final String name;

  /// Reprezentare vizuală. Material nu are icoane de instrumente, așa că
  /// folosim emoji — depictări literale, randate de fontul de sistem.
  final String emoji;

  /// Acordajele disponibile. Primul e cel implicit.
  final List<Tuning> tunings;

  /// Numărul de corzi (note distincte) — derivat din primul acordaj.
  int get stringCount => tunings.first.notes.length;

  // Chitară
  static const guitar = Instrument(
    id: 'guitar',
    name: 'Chitară',
    emoji: '🎸',
    tunings: [
      Tuning(name: 'Standard', notes: ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']),
      Tuning(name: 'Drop D', notes: ['D2', 'A2', 'D3', 'G3', 'B3', 'E4']),
      Tuning(name: 'Open G', notes: ['D2', 'G2', 'D3', 'G3', 'B3', 'D4']),
      Tuning(name: 'DADGAD', notes: ['D2', 'A2', 'D3', 'G3', 'A3', 'D4']),
    ],
  );

  // Chitară bass (4 corzi)
  static const bass = Instrument(
    id: 'bass',
    name: 'Chitară bass',
    emoji: '🎸',
    tunings: [
      Tuning(name: 'Standard', notes: ['E1', 'A1', 'D2', 'G2']),
      Tuning(name: 'Drop D', notes: ['D1', 'A1', 'D2', 'G2']),
    ],
  );

  // Vioară
  static const violin = Instrument(
    id: 'violin',
    name: 'Vioară',
    emoji: '🎻',
    tunings: [
      Tuning(name: 'Standard', notes: ['G3', 'D4', 'A4', 'E5']),
    ],
  );

  // Ukulele (acordaj C, reentrant)
  static const ukulele = Instrument(
    id: 'ukulele',
    name: 'Ukulele',
    emoji: '🎸',
    tunings: [
      Tuning(name: 'Standard (C)', notes: ['G4', 'C4', 'E4', 'A4']),
    ],
  );

  // Mandolină (4 cursuri)
  static const mandolin = Instrument(
    id: 'mandolin',
    name: 'Mandolină',
    emoji: '🪕',
    tunings: [
      Tuning(name: 'Standard', notes: ['G3', 'D4', 'A4', 'E5']),
    ],
  );

  static const List<Instrument> all = [
    guitar,
    bass,
    violin,
    ukulele,
    mandolin,
  ];

  /// Caută un instrument după id; revine la chitară dacă id-ul e necunoscut.
  static Instrument byId(String id) =>
      all.firstWhere((i) => i.id == id, orElse: () => guitar);
}
