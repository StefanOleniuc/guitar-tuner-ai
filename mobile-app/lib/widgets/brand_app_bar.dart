import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import 'app_logo_banner.dart';
import 'sign_up_badge.dart';

/// AppBar comun pentru ecranele „permanente" (Acordor, Metronom).
///
/// Layout simetric:
///   * stânga  → pastilă „Sign up" (vizibilă doar dacă nu ești logat)
///   * centru  → wordmark „GTune AI"
///   * dreapta → icon Setări (opțional — pe ecrane care n-au sens setări
///     specifice, ca Metronomul, ascundem iconul prin `showSettings: false`)
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandAppBar({super.key, this.onSettings, this.showSettings = true});

  /// Callback custom pentru butonul de Setări — dacă lipsește,
  /// deschide [SettingsScreen] direct.
  final VoidCallback? onSettings;

  /// Afișează iconul de Setări (default `true`). Treci `false` pe
  /// ecrane unde Setările nu au sens contextual (ex. Metronom).
  final bool showSettings;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      leadingWidth: SignUpBadge.leadingWidth,
      leading: const SignUpBadge(),
      title: const AppLogoBanner(),
      actions: showSettings
          ? [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: onSettings ?? () => _openSettings(context),
              ),
            ]
          : null,
    );
  }

  static void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }
}
