import 'package:flutter/material.dart';

/// Estompare premium peste partea de sus a unui ecran, în spatele unui
/// AppBar transparent (cu `extendBodyBehindAppBar: true`).
///
/// Așezată ca ultimul copil al unui `Stack` (deasupra conținutului
/// scrollabil), ea desenează un gradient opac → transparent care:
///   1. ascunde elegant textul care urcă pe sub titlul AppBar-ului,
///   2. dă o senzație de „glass header" modern, fără sticker contrast.
///
/// `IgnorePointer` ca să nu fure tap-urile destinate AppBar-ului
/// (text + butoane în slot-ul actions).
class TopHeaderFade extends StatelessWidget {
  const TopHeaderFade({
    super.key,
    required this.color,
    this.extraHeight = 8,
  });

  /// Culoarea de fundal a ecranului — vârful gradient-ului e opac în
  /// această culoare, iar baza e complet transparent.
  final Color color;

  /// Lungime suplimentară sub AppBar pentru un taper și mai lin.
  final double extraHeight;

  @override
  Widget build(BuildContext context) {
    // Estompare scurtă și smooth — opac în zona AppBar, taper rapid jos.
    // Înălțime totală = padding status + AppBar + un mic taper extra.
    final topPadding = MediaQuery.of(context).padding.top;
    final height = topPadding + kToolbarHeight + extraHeight;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withAlpha(235),
                color.withAlpha(160),
                color.withAlpha(0),
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
