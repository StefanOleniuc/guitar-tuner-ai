import 'dart:math';

/// One Euro Filter (Casiez et al., 2012) — standard industrie pentru
/// semnale interactive zgomotoase: filtrează puternic jitter-ul când
/// valoarea e stabilă, dar urmărește rapid schimbările reale.
/// Aici îl folosim pe frecvență, ca acul tunerului să nu „danseze"
/// când coarda susținută e de fapt stabilă.
class OneEuroFilter {
  OneEuroFilter({
    this.minCutoff = 0.85,
    this.beta = 0.05,
    this.dCutoff = 1.0,
  });

  /// Cutoff minim (Hz) — mai mic = mai lin la valori stabile.
  final double minCutoff;

  /// Cât de agresiv crește cutoff-ul când valoarea chiar se schimbă.
  final double beta;

  /// Cutoff pentru derivată.
  final double dCutoff;

  double? _xPrev;
  double? _dxPrev;
  int? _tPrevMs;

  void reset() {
    _xPrev = null;
    _dxPrev = null;
    _tPrevMs = null;
  }

  double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  double filter(double x, int tMs) {
    if (_tPrevMs == null) {
      _tPrevMs = tMs;
      _xPrev = x;
      _dxPrev = 0;
      return x;
    }

    double dt = (tMs - _tPrevMs!) / 1000.0;
    if (dt <= 0) dt = 0.016;

    final dx = (x - _xPrev!) / dt;
    final aD = _alpha(dCutoff, dt);
    final dxHat = _dxPrev! + aD * (dx - _dxPrev!);

    final cutoff = minCutoff + beta * dxHat.abs();
    final aX = _alpha(cutoff, dt);
    final xHat = _xPrev! + aX * (x - _xPrev!);

    _xPrev = xHat;
    _dxPrev = dxHat;
    _tPrevMs = tMs;
    return xHat;
  }
}
