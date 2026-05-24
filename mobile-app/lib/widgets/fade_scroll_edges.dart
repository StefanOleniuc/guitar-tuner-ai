import 'package:flutter/material.dart';

/// Estompează lin marginile (sus + jos) ale unui conținut scrollabil, ca
/// textul să se „topească" în loc să se taie brusc peste AppBar sau la
/// baza ecranului.
///
/// Folosește un `ShaderMask` cu gradient vertical de opacitate
/// (`BlendMode.dstIn`). Reutilizabil pe orice ecran cu listă/scroll.
class FadeScrollEdges extends StatelessWidget {
  const FadeScrollEdges({
    super.key,
    required this.child,
    this.topFade = 0.11,
    this.bottomFade = 0.055,
  });

  final Widget child;

  /// Fracția din înălțime pe care se estompează marginea de sus / de jos.
  final double topFade;
  final double bottomFade;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect rect) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, topFade, 1.0 - bottomFade, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}
