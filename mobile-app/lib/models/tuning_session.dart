/// O sesiune de acordaj completată, înregistrată în istoric.
class TuningSession {
  const TuningSession({
    required this.id,
    required this.instrument,
    required this.tuningName,
    required this.stringsTuned,
    required this.totalStrings,
    required this.durationSeconds,
    required this.a4,
    required this.createdAt,
  });

  final int id;
  final String instrument;
  final String tuningName;
  final int stringsTuned;
  final int totalStrings;
  final double durationSeconds;
  /// Calibrare A4 folosită în sesiune (Hz). `440` = standard internațional.
  final double a4;
  final DateTime createdAt; // UTC ISO din backend

  /// Toate corzile au fost acordate.
  bool get isComplete => stringsTuned >= totalStrings;

  /// A4 e diferit de 440 Hz standard → util de afișat în istoric.
  bool get hasCustomA4 => (a4 - 440.0).abs() > 0.5;

  factory TuningSession.fromJson(Map<String, dynamic> j) => TuningSession(
        id: j['id'] as int,
        instrument: j['instrument'] as String,
        tuningName: j['tuning_name'] as String,
        stringsTuned: j['strings_tuned'] as int,
        totalStrings: j['total_strings'] as int,
        durationSeconds: (j['duration_seconds'] as num).toDouble(),
        a4: (j['a4'] as num?)?.toDouble() ?? 440.0,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}
