import 'package:flutter/material.dart';

/// Fundalul comun al aplicației.
///
/// Bază SOLIDĂ (negru profund) — fără gradient liniar, deci fără benzile
/// vizibile de „color banding" pe ecranele OLED. Adâncimea „modernă" vine
/// din două glow-uri radiale difuze (verde sus-dreapta, mov jos-stânga),
/// fiecare cu falloff în 3 trepte ca să fie netede, fără cercuri vizibile.
///
/// Se folosește ca primul copil într-un `Stack`, sub conținut.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  /// Negru profund, aproape pur — uniform, fără benzi.
  static const Color base = Color(0xFF060608);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: base,
      child: SizedBox.expand(
        child: Stack(
          children: [
            // Glow verde, difuz, sus-dreapta
            Positioned(
              top: -150,
              right: -110,
              child: _Glow(color: Color(0xFF00E676), size: 330, peak: 26),
            ),
            // Glow mov (AI), difuz, jos-stânga
            Positioned(
              bottom: -170,
              left: -130,
              child: _Glow(color: Color(0xFF7C4DFF), size: 360, peak: 30),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cerc cu gradient radial neted (falloff în 3 trepte → fără inel vizibil).
class _Glow extends StatelessWidget {
  const _Glow({
    required this.color,
    required this.size,
    required this.peak,
  });

  final Color color;
  final double size;

  /// Alpha maxim (în centru). Glow-ul se stinge complet la margine.
  final int peak;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          stops: const [0.0, 0.45, 0.75, 1.0],
          colors: [
            color.withAlpha(peak),
            color.withAlpha((peak * 0.45).round()),
            color.withAlpha((peak * 0.14).round()),
            color.withAlpha(0),
          ],
        ),
      ),
    );
  }
}
