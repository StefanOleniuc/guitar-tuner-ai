import 'package:flutter/material.dart';

import '../models/instrument.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/user_data_service.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/persistent_feature_bar.dart';
import 'settings_screen.dart';
import 'tuning_history_screen.dart';

const Color _green = Color(0xFF00E676);
const Color _track = Color(0xFF2A2A2A);
const Color _card = Color(0x14FFFFFF);

/// Ecranul „Cont" — vizibil ca al 3-lea tab swipeable când utilizatorul
/// e autentificat. Înlocuiește redirectul către Setări care era confuz
/// (userul tap pe „Cont" → primea Setări).
///
/// Conține: profil, statistici personale (sesiuni, instrument, A4),
/// scurtături către Setări și Istoric acordaje, buton de deconectare
/// cu confirmare.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.inTab = false});

  /// `true` când e afișat ca pagină în `PageView`-ul shell-ului (rezervă
  /// spațiu pentru bara persistentă). `false` când e push (deși momentan
  /// nu îl pushăm de nicăieri — păstrăm flag-ul ca opțiune).
  final bool inTab;

  /// Dialog modern de editare a numelui afișat. Salvează prin
  /// `AuthService.updateDisplayName` (backend PUT /api/auth/me).
  Future<void> _editDisplayName(BuildContext context, String current) async {
    // Dialog-ul își deține propriul TextEditingController — îl creează în
    // initState și îl disposez în dispose, după ce tree-ul e demontat.
    // (Disposing-ul aici, după `await showDialog`, e PREA devreme: dialog-ul
    // se află încă în mijlocul rebuild-ului de închidere → assertion
    // `_dependents.isEmpty` eșua.)
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withAlpha(170),
      builder: (ctx) => _EditNameDialog(initialValue: current),
    );
    if (result == null) return;
    final err = await AuthService.instance.updateDisplayName(result);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 3)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      // AppBar fără setări (Cont propriu nu are setări — sunt în Setări).
      appBar: const BrandAppBar(showSettings: false),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          AuthService.instance,
          UserDataService.instance,
          AppSettings.instance,
        ]),
        builder: (context, _) {
          final user = AuthService.instance.user;
          if (user == null) {
            // Edge case — userul s-a delogat exact pe acest tab.
            return const SizedBox.shrink();
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              MediaQuery.of(context).padding.top + kToolbarHeight + 18,
              18,
              PersistentFeatureBar.reservedHeight(context),
            ),
            children: [
              _ProfileHeader(
                name: user.label,
                email: user.email,
                initial: user.initial,
                onEdit: () => _editDisplayName(context, user.label),
              ),
              const SizedBox(height: 24),
              // Non-const: depinde de AppSettings (instrument + A4) — fără
              // const Flutter rebuild-uiește când AnimatedBuilder fires;
              // cu const widget-ul e cache-uit și nu reflectă schimbările.
              _StatsRow(),
              const SizedBox(height: 24),
              _ActionTile(
                icon: Icons.history_rounded,
                label: 'Istoric acordaje',
                trailing: '${UserDataService.instance.historyTotal}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TuningHistoryScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _ActionTile(
                icon: Icons.settings_outlined,
                label: 'Setări',
                trailing: null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _LogoutButton(onTap: () => confirmAndLogout(context)),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.initial,
    required this.onEdit,
  });

  final String name;
  final String email;
  final String initial;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar sobru: cerc întunecat cu border discret și inițială albă.
        // Fără halou neon — design liniștit, modern, nu țipător.
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1E1E24),
            border: Border.all(color: Colors.white.withAlpha(28), width: 1),
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 34,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Nume + iconiță de editare lângă (TextButton inline) — clear,
        // discoverable, fără un întreg menu pentru profil.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            InkResponse(
              onTap: onEdit,
              radius: 18,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.edit_outlined,
                  size: 17,
                  color: Colors.white54,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          email,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final inst = AppSettings.instance.instrument;
    final a4 = AppSettings.instance.a4;
    final total = UserDataService.instance.historyTotal;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.graphic_eq_rounded,
            value: '$total',
            label: total == 1 ? 'acordaj' : 'acordaje',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: _iconForInstrument(inst),
            value: _shortInstrument(inst),
            label: 'instrument',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.tune_rounded,
            value: '${a4.toStringAsFixed(0)} Hz',
            label: 'referință A4',
          ),
        ),
      ],
    );
  }

  static IconData _iconForInstrument(Instrument i) {
    switch (i.id) {
      case 'bass':
        return Icons.queue_music_rounded;
      case 'violin':
        return Icons.music_note_rounded;
      case 'ukulele':
        return Icons.audiotrack_rounded;
      case 'mandolin':
        return Icons.library_music_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }

  static String _shortInstrument(Instrument i) {
    switch (i.id) {
      case 'guitar':
        return 'Chitară';
      case 'bass':
        return 'Bas';
      case 'violin':
        return 'Vioară';
      case 'ukulele':
        return 'Ukulele';
      case 'mandolin':
        return 'Mandolină';
      default:
        return i.name;
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _track),
      ),
      child: Column(
        children: [
          Icon(icon, color: _green, size: 22),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _track),
          ),
          child: Row(
            children: [
              Icon(icon, color: _green, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) ...[
                Text(
                  trailing!,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog modern pentru editarea numelui afișat — același limbaj vizual
/// ca restul popup-urilor (card întunecat cu sticlă, buton verde).
class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.initialValue});
  final String initialValue;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF18181F),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withAlpha(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Modifică numele afișat',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 60,
              cursorColor: _green,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Numele tău',
                hintStyle: const TextStyle(color: Colors.white38),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withAlpha(14),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withAlpha(40)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _green, width: 1.5),
                ),
              ),
              onSubmitted: (v) => Navigator.of(context).pop(_controller.text),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withAlpha(50)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Anulează',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Salvează',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text('Deconectează-te'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: BorderSide(color: Colors.white.withAlpha(40)),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
