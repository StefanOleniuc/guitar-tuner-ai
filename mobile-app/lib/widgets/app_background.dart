import 'package:flutter/material.dart';

/// Fundal comun al aplicației: gradient întunecat + două glow-uri
/// difuze (verde sus-dreapta, mov jos-stânga). Dă adâncime ecranului
/// și oferă „material" pentru efectul de sticlă (glassmorphism) al
/// barelor de deasupra — un BackdropFilter are ce să estompeze.
///
/// Se folosește ca primul copil într-un `Stack`, sub conținut.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF17171E),
              Color(0xFF0C0C10),
              Color(0xFF080809),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Glow verde, difuz, sus-dreapta
            Positioned(
              top: -130,
              right: -100,
              child: _Glow(color: Color(0xFF00E676), size: 300, alpha: 30),
            ),
            // Glow mov (AI), difuz, jos-stânga
            Positioned(
              bottom: -150,
              left: -120,
              child: _Glow(color: Color(0xFF9C27B0), size: 340, alpha: 34),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un cerc cu gradient radial — de la culoare translucidă la transparent.
class _Glow extends StatelessWidget {
  const _Glow({
    required this.color,
    required this.size,
    required this.alpha,
  });

  final Color color;
  final double size;
  final int alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withAlpha(alpha), color.withAlpha(0)],
        ),
      ),
    );
  }
}
