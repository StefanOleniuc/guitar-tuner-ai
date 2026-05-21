class PitchResult {
  const PitchResult({
    required this.frequency,
    required this.pitched,
    required this.probability,
  });

  final double frequency;
  final bool pitched;
  final double probability;

  factory PitchResult.empty() => const PitchResult(
        frequency: 0,
        pitched: false,
        probability: 0,
      );
}
