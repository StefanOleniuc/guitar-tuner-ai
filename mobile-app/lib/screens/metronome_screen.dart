import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/active_page.dart';
import '../services/metronome_engine.dart';
import '../utils/app_logger.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/persistent_feature_bar.dart';

const Color _green = Color(0xFF00E676);
const Color _track = Color(0xFF2A2A2A);
const Color _card = Color(0x14FFFFFF); // alb 8%

const int _minBpm = 40;
const int _maxBpm = 240;

/// Ecranul de Metronom: tempo (BPM), măsură, indicator vizual de bătaie,
/// click audio (accent pe bătaia 1), tap-tempo.
class MetronomeScreen extends StatefulWidget {
  const MetronomeScreen({super.key});

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final MetronomeEngine _engine = MetronomeEngine();
  late final AnimationController _pulse;
  bool _ready = false;
  int _activeBeat = -1;
  final List<DateTime> _taps = [];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1,
    );
    _engine.onBeat = _onBeat;
    _engine.init().then((_) {
      if (mounted) setState(() => _ready = true);
    });
    // Ascultăm tab-ul activ — oprim metronomul când nu mai e vizibil
    // (swipe spre Acordor sau Setări/Cont pushed peste shell). Userul îl
    // pornește înapoi cu butonul Play când revine.
    ActivePage.instance.addListener(_onActivePageChanged);
    // Lifecycle: pauză când app trece în background (alt-tab / lock screen)
    // — altfel difuzorul continuă să țăcăne deși userul nu mai e în app.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ActivePage.instance.removeListener(_onActivePageChanged);
    _pulse.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _engine.isRunning) {
      AppLogger.i('[Metronome] App în background — opresc click-ul');
      setState(() {
        _engine.stop();
        _activeBeat = -1;
      });
    }
  }

  /// Oprim metronomul când tab-ul iese din vizibilitate — altfel sunetul
  /// rămâne agresiv pe Acordor (cu microfonul activ) sau în Setări.
  void _onActivePageChanged() {
    if (!mounted) return;
    final isVisible =
        ActivePage.instance.visibleIndex == ActivePage.metronomeIndex;
    if (!isVisible && _engine.isRunning) {
      AppLogger.i('[MetronomeScreen] Tab ascuns — opresc metronomul');
      setState(() {
        _engine.stop();
        _activeBeat = -1;
      });
    }
  }

  void _onBeat(int beatInBar, bool accent) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _pulse.forward(from: 0);
    setState(() => _activeBeat = beatInBar);
  }

  void _toggleRun() {
    HapticFeedback.mediumImpact();
    setState(() {
      if (_engine.isRunning) {
        _engine.stop();
        _activeBeat = -1;
      } else {
        _engine.start();
      }
    });
  }

  void _changeBpm(int delta) {
    final next = (_engine.bpm + delta).clamp(_minBpm, _maxBpm);
    if (next == _engine.bpm) return;
    HapticFeedback.selectionClick();
    setState(() => _engine.bpm = next);
  }

  void _setBeatsPerBar(int v) {
    HapticFeedback.selectionClick();
    setState(() => _engine.beatsPerBar = v);
  }

  /// Tap-tempo: din intervalele dintre ultimele apăsări deducem BPM-ul.
  void _tapTempo() {
    final now = DateTime.now();
    HapticFeedback.selectionClick();
    setState(() {
      if (_taps.isNotEmpty &&
          now.difference(_taps.last) > const Duration(seconds: 2)) {
        _taps.clear(); // pauză lungă → sesiune nouă de tapping
      }
      _taps.add(now);
      if (_taps.length > 5) _taps.removeAt(0);

      if (_taps.length >= 2) {
        var totalMs = 0;
        for (int i = 1; i < _taps.length; i++) {
          totalMs += _taps[i].difference(_taps[i - 1]).inMilliseconds;
        }
        final avg = totalMs / (_taps.length - 1);
        if (avg > 0) {
          final bpm = (60000 / avg).round().clamp(_minBpm, _maxBpm);
          AppLogger.d('[Metronome] Tap-tempo → $bpm BPM');
          _engine.bpm = bpm;
        }
      }
    });
  }

  String get _tempoName {
    final b = _engine.bpm;
    if (b < 60) return 'Largo';
    if (b < 72) return 'Adagio';
    if (b < 92) return 'Andante';
    if (b < 120) return 'Moderato';
    if (b < 152) return 'Allegro';
    if (b < 184) return 'Vivace';
    return 'Presto';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fundalul îl pictează `MainShell` unitar sub `PageView` (fără
      // cusături la swipe între taburi).
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      // AppBar comun (logo + Sign up), DAR fără iconul Setări — pe
      // Metronom nu are sens contextual (setările sunt pentru Acordor).
      appBar: const BrandAppBar(showSettings: false),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  _buildBpmRow(),
                  const SizedBox(height: 30),
                  _buildBeatDots(),
                  const SizedBox(height: 38),
                  _buildPlayButton(),
                  const Spacer(flex: 2),
                  _buildBeatsSelector(),
                  const SizedBox(height: 18),
                  _buildTapTempo(),
                  const Spacer(flex: 1),
                  // Rezervăm spațiu pentru bara persistentă plutitoare.
                  SizedBox(
                    height: PersistentFeatureBar.reservedHeight(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // BPM mare + tempo, flancat de − / +
  Widget _buildBpmRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _HoldButton(
          icon: Icons.remove,
          enabled: _engine.bpm > _minBpm,
          onStep: () => _changeBpm(-1),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_engine.bpm}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 68,
                fontWeight: FontWeight.bold,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'BPM  ·  $_tempoName',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        _HoldButton(
          icon: Icons.add,
          enabled: _engine.bpm < _maxBpm,
          onStep: () => _changeBpm(1),
        ),
      ],
    );
  }

  // Punctele de bătaie (poziția în măsură)
  Widget _buildBeatDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_engine.beatsPerBar, (i) {
        final active = i == _activeBeat;
        final accent = i == 0;
        final color = accent ? _green : Colors.white;
        final size = active ? 18.0 : 11.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : color.withAlpha(40),
              // Fără BoxShadow — pe AMOLED, blur-ul activ alterna pe fiecare
              // bătaie și se vedea ca o pâlpâire slabă pe tot ecranul.
            ),
          ),
        );
      }),
    );
  }

  // Butonul Play / Stop — pulsează pe fiecare bătaie
  Widget _buildPlayButton() {
    final running = _engine.isRunning;
    return GestureDetector(
      onTap: _ready ? _toggleRun : null,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          // _pulse: 0 imediat după bătaie → 1 la final. „Pop" descrescător.
          final pop = running ? (1 - _pulse.value) : 0.0;
          return Transform.scale(
            scale: 1.0 + 0.05 * pop,
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Alpha constant — modulația pe fiecare bătaie cauza
                // recompoziție de layer și pâlpâire pe AMOLED.
                color: _green.withAlpha(38),
                border: Border.all(color: _green.withAlpha(170), width: 2),
              ),
              child: Icon(
                running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: _green,
                size: 56,
              ),
            ),
          );
        },
      ),
    );
  }

  // Selector bătăi pe măsură (2..7)
  Widget _buildBeatsSelector() {
    return Column(
      children: [
        const Text(
          'BĂTĂI PE MĂSURĂ',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final n in [2, 3, 4, 5, 6, 7])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => _setBeatsPerBar(n),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _engine.beatsPerBar == n ? _green : _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _engine.beatsPerBar == n ? _green : _track,
                      ),
                    ),
                    child: Text(
                      '$n',
                      style: TextStyle(
                        color: _engine.beatsPerBar == n
                            ? Colors.black
                            : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Tap-tempo
  Widget _buildTapTempo() {
    return _TapTempoButton(onTap: _tapTempo, recentTaps: _taps.length);
  }
}

/// Buton „Tap tempo" cu feedback vizibil pe atingere:
///   * **scale 0.94** + **flash verde** prin culoarea de fundal / border
///   * ripple Material (`InkWell`) — afișează zona pe care s-a apăsat
///   * **3 dots indicator** care se umplu pe măsură ce tap-urile cresc,
///     ca să-i arate userului că app-ul „a auzit" apăsarea
class _TapTempoButton extends StatefulWidget {
  const _TapTempoButton({required this.onTap, required this.recentTaps});

  final VoidCallback onTap;

  /// Numărul de tap-uri din sesiunea curentă (resetat după 2s inactivitate
  /// în `_tapTempo`). Folosit ca să umplem indicatoarele de progres.
  final int recentTaps;

  @override
  State<_TapTempoButton> createState() => _TapTempoButtonState();
}

class _TapTempoButtonState extends State<_TapTempoButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value; // 0..1 → 0
        // Ramp triunghiular: 0→1→0 peste durata animației.
        final pulse = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
        final scale = 1.0 - 0.06 * pulse;
        return Transform.scale(
          scale: scale,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _handleTap,
              borderRadius: BorderRadius.circular(22),
              splashColor: _green.withAlpha(70),
              highlightColor: _green.withAlpha(30),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Color.lerp(_card, _green.withAlpha(60), pulse * 0.85),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color:
                        Color.lerp(
                          _track,
                          _green,
                          (pulse * 0.85).clamp(0.0, 1.0),
                        ) ??
                        _track,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      color: Color.lerp(Colors.white60, _green, pulse),
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tap tempo',
                      style: TextStyle(
                        color: Color.lerp(Colors.white70, _green, pulse),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Indicator: 4 puncte care se umplu pe măsură ce
                    // tap-urile cresc — la 4+ tap-uri toate sunt verzi.
                    _TapDots(activeCount: widget.recentTaps),
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

class _TapDots extends StatelessWidget {
  const _TapDots({required this.activeCount});

  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final on = i < activeCount;
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? _green : Colors.white24,
            ),
          ),
        );
      }),
    );
  }
}

/// Buton rotund cu animație de apăsare + hold-to-repeat (pentru BPM).
class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.icon,
    required this.onStep,
    required this.enabled,
  });

  final IconData icon;
  final VoidCallback onStep;
  final bool enabled;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _pressed = false;
  Timer? _holdDelay;
  Timer? _repeat;

  void _down() {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    widget.onStep();
    _holdDelay = Timer(const Duration(milliseconds: 360), () {
      _repeat = Timer.periodic(
        const Duration(milliseconds: 70),
        (_) => widget.enabled ? widget.onStep() : _stop(),
      );
    });
  }

  void _up() {
    if (_pressed) setState(() => _pressed = false);
    _stop();
  }

  void _stop() {
    _holdDelay?.cancel();
    _repeat?.cancel();
    _holdDelay = null;
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: AnimatedScale(
        scale: _pressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed ? _green.withAlpha(55) : const Color(0xFF1F1F1F),
            border: Border.all(color: _pressed ? _green : _track, width: 1.6),
          ),
          child: Icon(
            widget.icon,
            size: 28,
            color: !on ? Colors.white12 : (_pressed ? _green : Colors.white70),
          ),
        ),
      ),
    );
  }
}
