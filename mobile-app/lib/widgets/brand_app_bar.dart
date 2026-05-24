import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../services/active_page.dart';
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
      // Tap pe wordmark → shortcut „Home" către Acordor. E intuitiv
      // (logo-ul e mereu un home-button în app-uri moderne) și ajută
      // userii care nu observă bara de jos.
      title: InkWell(
        onTap: () => ActivePage.instance.requestTab(ActivePage.tunerIndex),
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: AppLogoBanner(),
        ),
      ),
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }
}
