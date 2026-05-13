import 'dart:math';
import 'dart:typed_data';

class AudioUtils {
  AudioUtils._();

  /// Calculează Root Mean Square din buffer PCM16 little-endian.
  /// Returnează 0.0 dacă buffer-ul e gol sau are mai puțin de 2 bytes.
  static double calculateRMS(Uint8List pcm16Bytes) {
    if (pcm16Bytes.length < 2) return 0.0;

    final byteData = ByteData.sublistView(pcm16Bytes);
    double sumOfSquares = 0.0;
    int sampleCount = 0;

    for (int i = 0; i + 1 < pcm16Bytes.length; i += 2) {
      // Int16 signed little-endian, range [-32768, +32767]
      final sample = byteData.getInt16(i, Endian.little);
      sumOfSquares += sample * sample;
      sampleCount++;
    }

    if (sampleCount == 0) return 0.0;
    return sqrt(sumOfSquares / sampleCount);
  }

  /// Normalizează RMS la intervalul [0.0, 1.0].
  /// Valoarea maximă absolută pentru PCM16 signed este 32768.
  static double rmsToNormalized(double rms) {
    return (rms / 32768.0).clamp(0.0, 1.0);
  }
}
