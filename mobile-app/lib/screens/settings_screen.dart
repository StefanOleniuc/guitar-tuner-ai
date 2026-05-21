import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/instrument.dart';
import '../services/app_settings.dart';
import '../utils/app_logger.dart';
import '../widgets/app_background.dart';

// Paletă — aceeași ca în tuner_screen, ținută local ca să nu cuplăm
// ecranele între ele.
const Color _bg = Color(0xFF0D0D0D);
const Color _green = Color(0xFF00E676);
const Color _track = Color(0xFF2A2A2A);

/// Ecranul de Setări: alegerea instrumentului + calibrarea A4.
/// Restul (cont, limbă, notificări) vine în iterații ulterioare.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Setări',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
      ),
      body: Stack(
        children: const [
          AppBackground(),
          _SettingsList(),
        ],
      ),
    );
  }
}

/// Lista de setări — extrasă ca widget `const` separat ca să nu cuplăm
/// `const`-ul ei de Stack-ul părinte.
class _SettingsList extends StatelessWidget {
  const _SettingsList();

  @override
  Widget build(BuildContext context) {
    // Fiecare widget reactiv își are propriul AnimatedBuilder pe
    // AppSettings → pot rămâne `const` și totuși se reconstruiesc la
    // fiecare notificare.
    return ListView(
      // Top: status bar + AppBar transparent (body e extins în spate).
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.of(context).padding.top + kToolbarHeight + 8,
        18,
        32,
      ),
      children: const [
        _SectionLabel(icon: Icons.piano, text: 'Instrument'),
        SizedBox(height: 10),
        _InstrumentPicker(),
        SizedBox(height: 28),
        _SectionLabel(icon: Icons.tune, text: 'Calibrare'),
        SizedBox(height: 10),
        _A4CalibrationCard(),
        SizedBox(height: 28),
        _SectionLabel(icon: Icons.visibility_outlined, text: 'Afișaj'),
        SizedBox(height: 10),
        _DisplayCard(),
        SizedBox(height: 28),
        _AboutFooter(),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────
// Etichetă de secțiune
// ───────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: _green),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────
// Selectorul de instrument
// ───────────────────────────────────────────────────────────────────
class _InstrumentPicker extends StatelessWidget {
  const _InstrumentPicker();

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder propriu → se reconstruiește când AppSettings notifică.
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final selectedId = AppSettings.instance.instrumentId;
        return Column(
          children: [
            for (final inst in Instrument.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _InstrumentTile(
                  instrument: inst,
                  selected: inst.id == selectedId,
                  onTap: () => _selectAndReturn(context, inst),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Selectează instrumentul și revine pe ecranul tunerului — utilizatorul
  /// vede instant noul instrument acordat.
  void _selectAndReturn(BuildContext context, Instrument inst) {
    HapticFeedback.selectionClick();
    AppSettings.instance.setInstrument(inst.id);
    AppLogger.i('⚙️ [Settings] Instrument selectat: ${inst.name}');
    // Mic delay ca să se vadă animația de selecție, apoi înapoi la tuner.
    Future.delayed(const Duration(milliseconds: 260), () {
      if (context.mounted) Navigator.of(context).maybePop();
    });
  }
}

class _InstrumentTile extends StatelessWidget {
  const _InstrumentTile({
    required this.instrument,
    required this.selected,
    required this.onTap,
  });

  final Instrument instrument;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tuningNames = instrument.tunings.map((t) => t.name).join(' · ');
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _green.withAlpha(22) : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _green : _track,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _green.withAlpha(40) : _track,
              ),
              child: Text(
                instrument.emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instrument.name,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${instrument.stringCount} corzi  ·  $tuningNames',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            // Bulina radio animată
            AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _green : Colors.transparent,
                border: Border.all(
                  color: selected ? _green : _track,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.black)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────
// Cardul de calibrare A4 cu butoane +/− animate
// ───────────────────────────────────────────────────────────────────
class _A4CalibrationCard extends StatelessWidget {
  const _A4CalibrationCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final a4 = AppSettings.instance.a4;
        final isStandard = a4 == AppSettings.defaultA4;
        final delta = (a4 - AppSettings.defaultA4).round();

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _track),
          ),
          child: Column(
            children: [
              const Text(
                'Referință A4',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StepButton(
                    icon: Icons.remove,
                    enabled: a4 > AppSettings.minA4,
                    onStep: () => _nudge(-1),
                  ),
                  // Numărul mare — animă la fiecare schimbare
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: Tween<double>(begin: 0.65, end: 1.0).animate(
                          CurvedAnimation(
                              parent: anim, curve: Curves.easeOutBack),
                        ),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Column(
                        key: ValueKey<int>(a4.round()),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            a4.round().toString(),
                            style: const TextStyle(
                              color: _green,
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              height: 1,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Text(
                            'Hz',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add,
                    enabled: a4 < AppSettings.maxA4,
                    onStep: () => _nudge(1),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isStandard
                        ? 'Standard internațional (440 Hz)'
                        : 'Calibrat — abatere ${delta > 0 ? '+' : ''}$delta Hz',
                    style: TextStyle(
                      color: isStandard ? Colors.white38 : _green,
                      fontSize: 12,
                    ),
                  ),
                  if (!isStandard) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        AppSettings.instance.resetA4();
                      },
                      child: const Text(
                        'Resetează',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _nudge(int delta) {
    HapticFeedback.selectionClick();
    AppSettings.instance.setA4(AppSettings.instance.a4 + delta);
  }
}

// ───────────────────────────────────────────────────────────────────
// Cardul de afișaj — comutator pentru frecvența (Hz)
// ───────────────────────────────────────────────────────────────────
class _DisplayCard extends StatelessWidget {
  const _DisplayCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final on = AppSettings.instance.showFrequency;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _track),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Afișează frecvența',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Valoarea în Hz sub notă, pe tuner',
                      style: TextStyle(color: Colors.white38, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                activeThumbColor: Colors.black,
                activeTrackColor: _green,
                inactiveThumbColor: Colors.white70,
                inactiveTrackColor: _track,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  AppSettings.instance.setShowFrequency(v);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Buton circular +/− cu animație de apăsare și hold-to-repeat.
class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.onStep,
    required this.enabled,
  });

  final IconData icon;
  final VoidCallback onStep;
  final bool enabled;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _pressed = false;
  Timer? _holdDelay;
  Timer? _repeat;

  void _onDown() {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    widget.onStep();
    // Hold-to-repeat: după 380ms, repetă la 110ms cât e ținut apăsat.
    _holdDelay = Timer(const Duration(milliseconds: 380), () {
      _repeat = Timer.periodic(
        const Duration(milliseconds: 110),
        (_) => widget.enabled ? widget.onStep() : _stopRepeat(),
      );
    });
  }

  void _onUp() {
    if (_pressed) setState(() => _pressed = false);
    _stopRepeat();
  }

  void _stopRepeat() {
    _holdDelay?.cancel();
    _repeat?.cancel();
    _holdDelay = null;
    _repeat = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    return GestureDetector(
      onTapDown: (_) => _onDown(),
      onTapUp: (_) => _onUp(),
      onTapCancel: _onUp,
      child: AnimatedScale(
        scale: _pressed ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed ? _green.withAlpha(55) : const Color(0xFF1F1F1F),
            border: Border.all(
              color: _pressed ? _green : _track,
              width: 1.6,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 28,
            color: !on
                ? Colors.white12
                : (_pressed ? _green : Colors.white70),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────
// Footer „Despre"
// ───────────────────────────────────────────────────────────────────
class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        children: [
          Text(
            'Guitar Tuner AI',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Versiune 1.0.0',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
