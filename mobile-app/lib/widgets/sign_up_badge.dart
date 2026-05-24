import 'package:flutter/material.dart';

import '../screens/auth_screen.dart';
import '../services/auth_service.dart';

const Color _green = Color(0xFF00E676);
const Color _greenSoft = Color(0xFF1DE9B6);

/// Pastilă „Sign up" pentru header — încurajează crearea unui cont.
///
/// Stă în slotul `leading` al AppBar-ului (stânga titlului „GTune AI"),
/// simetric cu iconul de Setări din dreapta. Design static, modern și
/// curat — fără glow exterior sau efecte care „debordează" peste AppBar.
/// Se ascunde singur când utilizatorul e deja autentificat.
///
/// Folosește `leadingWidth: 112` pe AppBar pentru a încăpea cu confort.
class SignUpBadge extends StatelessWidget {
  const SignUpBadge({super.key});

  /// Lățimea recomandată a slotului `leading` pentru această pastilă.
  static const double leadingWidth = 112;

  void _openAuth(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        if (AuthService.instance.isAuthenticated) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openAuth(context),
              borderRadius: BorderRadius.circular(22),
              splashColor: Colors.white.withAlpha(50),
              highlightColor: Colors.white.withAlpha(24),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_green, _greenSoft],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_add_alt_1,
                      size: 14,
                      color: Colors.black,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Sign up',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
