import 'package:flutter/material.dart';

/// Wordmark tipografic „GTune AI" — minimalist, modern, clar la orice
/// dimensiune (text vectorial, nu imagine raster). Reutilizabil ca header.
class AppLogoBanner extends StatelessWidget {
  const AppLogoBanner({super.key, this.fontSize = 22});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
        children: const [
          TextSpan(text: 'GTune', style: TextStyle(color: Colors.white)),
          TextSpan(
            text: ' AI',
            style: TextStyle(color: Color(0xFF00E676)),
          ),
        ],
      ),
    );
  }
}
