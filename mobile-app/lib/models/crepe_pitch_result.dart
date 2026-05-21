/// Rezultatul unei verificări AI (CREPE) — frecvența fundamentală,
/// încrederea modelului (0..1) și durata semnalului analizat.
class CrepePitchResult {
  const CrepePitchResult({
    required this.frequency,
    required this.confidence,
    required this.durationMs,
  });

  final double frequency;
  final double confidence;
  final int durationMs;

  factory CrepePitchResult.fromJson(Map<String, dynamic> json) {
    return CrepePitchResult(
      frequency: (json['frequency'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      durationMs: (json['duration_ms'] as num).toInt(),
    );
  }

  @override
  String toString() =>
      'CrepePitchResult(${frequency.toStringAsFixed(2)}Hz, '
      'conf=${(confidence * 100).toStringAsFixed(0)}%, ${durationMs}ms)';
}
