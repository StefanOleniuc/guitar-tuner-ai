import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

const Color _green = Color(0xFF00E676);

/// Bara persistentă cu funcționalitățile aplicației (Acordor, Metronom,
/// Cont). Plutește deasupra conținutului, cu efect de sticlă, simetrică
/// cu marginile ecranului.
///
/// Elementele 0 și 1 sunt taburi (animă `PageView`-ul); elementul 2
/// („Cont") deschide ecranul de autentificare sau, dacă userul e logat,
/// secțiunea Cont din Setări — restrictiv, nu schimbă tab-ul.
class PersistentFeatureBar extends StatelessWidget {
  const PersistentFeatureBar({
    super.key,
    required this.activeIndex,
    required this.onTap,
  });

  final int activeIndex;
  final void Function(int) onTap;

  /// Înălțime totală rezervată (bară + margini + safe area de jos) —
  /// paginile o folosesc ca padding-bottom ca să nu se ascundă conținut
  /// sub bara plutitoare.
  static double reservedHeight(BuildContext context) {
    return 78 + MediaQuery.of(context).padding.bottom;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 10),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withAlpha(32)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _FeatureItem(
                    icon: Icons.graphic_eq,
                    label: 'Acordor',
                    active: activeIndex == 0,
                    onTap: () => onTap(0),
                  ),
                  _FeatureItem(
                    icon: Icons.av_timer,
                    label: 'Metronom',
                    active: activeIndex == 1,
                    onTap: () => onTap(1),
                  ),
                  _FeatureItem(
                    icon: Icons.account_circle_outlined,
                    label: 'Cont',
                    // Contul e tab swipeable (al 3-lea, când e present) →
                    // se colorează verde când e selectat.
                    active: activeIndex == 2,
                    onTap: () => onTap(2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? _green : Colors.white60;
    // GestureDetector simplu — fără ripple, fără animație de scale.
    // Userul a cerut „doar să se facă verzi" pe active. Cleaner, modern.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
