import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tuning.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/audio_service.dart';
import '../services/pitch_service.dart';
import '../utils/app_logger.dart';
import '../utils/one_euro_filter.dart';
import '../widgets/app_background.dart';
import '../widgets/app_logo_banner.dart';
import 'settings_screen.dart';

const Color _bg = Color(0xFF0D0D0D);
const Color _green = Color(0xFF00E676);
const Color _orange = Color(0xFFFF9800);
const Color _red = Color(0xFFF44336);
const Color _grey = Color(0xFF424242);
const Color _track = Color(0xFF2A2A2A);
// Paletă pentru verificarea AI (CREPE) — distinctă de verde/roșu YIN
const Color _aiPurple = Color(0xFF9C27B0);
const Color _aiCardBg = Color(0xFF1A0E2E);

// Cât de „lipicios" e indicatorul: fracția cu care se apropie de țintă
// la fiecare cadru (~60fps). Mai mic = mai lin dar mai lent.
const double _easing = 0.18;

// Resetare automată a sesiunii dacă nu se cântă nimic atâta timp.
const Duration _inactivityReset = Duration(seconds: 12);

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AudioService _audioService = AudioService();
  final PitchService _pitchService = PitchService();
  final ApiService _apiService = ApiService();

  // Inițializat în initState din instrumentul curent (AppSettings).
  late Tuning _tuning;
  // null = mod Auto (detectează coarda automat); altfel doar coarda fixată
  String? _lockedString;
  bool _listening = false;
  bool _permissionDenied = false;
  String _note = '';
  double _freq = 0;
  bool _hasSignal = false;

  // Valoarea măsurată (țintă) vs. valoarea afișată (interpolată lin)
  double _targetCents = 0;
  double _displayCents = 0;
  Color _displayColor = _grey;
  // Oscilator de respirație 0..1 (sinus) — animă placeholder-ul idle
  // și indicatorul AI; recalculat la fiecare cadru în _onFrame.
  double _breath = 0;
  // Ultima dată când un cadru YIN a fost ACCEPTAT (a trecut de gating).
  // Dacă AI Precision e ON și asta e vechi → CREPE „cară" singur acul.
  DateTime? _lastYinAcceptedTime;

  // Sesiune: corzile acordate rămân verzi până la reset
  final Set<String> _tunedStrings = {};
  bool _allTuned = false;

  final List<double> _recentFreqs = [];
  // Filtru adaptiv pe frecvență — elimină jitter-ul când e stabil
  final OneEuroFilter _euro = OneEuroFilter();
  // Histerezis „acordat" ca să nu pâlpâie verde/portocaliu la limită
  bool _inTuneHyst = false;
  // Confirmare susținută: marcăm coarda doar dacă stă stabil sub 5¢
  // pe aceeași notă atâtea cadre la rând (~0.5s la ~80ms/cadru).
  static const int _kInTuneFramesNeeded = 6;
  String? _tuneCandidate;
  int _inTuneStreak = 0;
  // Salt mare neconfirmat — îl reținem ca să cerem confirmare pe 2 cadre
  double? _pendingFreq;
  StreamSubscription<Uint8List>? _audioSubscription;

  // ─── AI Precision (CREPE) — mod CONTINUU ───────────────────────────
  //
  // Pe baza fluxului audio comun cu YIN, acumulăm ferestre de _kAiWindow
  // ms și le trimitem la backend. CREPE oferă un „hint" de frecvență cu
  // confidence — folosit ca:
  //   1) referință de octavă pentru folding-ul YIN (kill E2↔E4)
  //   2) anchor de stabilitate când YIN bate jitter în zgomot
  //   3) feedback vizual (badge AI pulsează la fiecare update bun)
  bool _aiPrecisionEnabled = false;
  final BytesBuilder _aiWindowBuffer = BytesBuilder(copy: false);
  bool _aiRequestInFlight = false;
  double? _aiFreqHint;
  DateTime? _aiHintTime;
  double _aiConfidence = 0;
  // Fereastra trimisă la backend: 1.2s @ 16kHz mono PCM16
  // = 1200 * 16000 * 2 / 1000 = 38400 bytes per request
  static const int _kAiSampleRate = 16000;
  static const int _kAiWindowMs = 1200;
  static const int _kAiWindowBytes = _kAiWindowMs * _kAiSampleRate * 2 ~/ 1000;
  // Cât rămâne „proaspăt" un hint AI. Ciclul CREPE real e ~2-2.5s
  // (1.2s fereastră + ~1.1s inferență), deci 3.5s acoperă confortabil.
  static const Duration _kAiHintFreshness = Duration(milliseconds: 3500);
  // Praguri pentru filtrul anti-spike: CREPE poate da false-positives
  static const double _kAiMinConfidence = 0.45;
  static const double _kAiMaxClampedCents = 49.5;

  DateTime? _lastValidDetection;
  static const Duration _holdDuration = Duration(milliseconds: 1500);

  Timer? _inactivityTimer;
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Instrument + calibrare A4 din preferințe (deja încărcate în main)
    _tuning = AppSettings.instance.instrument.tunings.first;
    _pitchService.a4 = AppSettings.instance.a4;
    AppSettings.instance.addListener(_onSettingsChanged);
    // 2.4s/ciclu — oscilatorul de respirație pentru placeholder + AI.
    // _onFrame rulează oricum la fiecare vsync (~60fps); durata afectează
    // doar viteza lui _ticker.value (faza de sinus).
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addListener(_onFrame);
    // Pornim captura automat, fără buton
    WidgetsBinding.instance.addPostFrameCallback((_) => _startListening());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppSettings.instance.removeListener(_onSettingsChanged);
    _inactivityTimer?.cancel();
    _ticker.dispose();
    _audioSubscription?.cancel();
    _audioService.dispose();
    super.dispose();
  }

  /// Reacție la schimbări din Setări (instrument sau calibrare A4).
  void _onSettingsChanged() {
    if (!mounted) return;
    _pitchService.a4 = AppSettings.instance.a4;
    final instTunings = AppSettings.instance.instrument.tunings;
    if (!instTunings.contains(_tuning)) {
      // Instrumentul s-a schimbat → acordajul vechi nu mai e valid
      AppLogger.i('🎸 [TunerScreen] Instrument nou — resetez acordajul');
      setState(() {
        _tuning = instTunings.first;
        _lockedString = null;
        _clearDetection();
        _tunedStrings.clear();
        _allTuned = false;
        _lastValidDetection = null;
        _lastYinAcceptedTime = null;
      });
    } else {
      // Doar A4 s-a schimbat → recalculăm afișajul cu noua referință
      setState(() {});
    }
  }

  /// Deschide Setările. Oprește microfonul cât suntem pe alt ecran
  /// (nu are sens să capturăm/trimitem la backend în fundal) și îl
  /// repornește la întoarcere.
  Future<void> _openSettings() async {
    AppLogger.i('⚙️ [TunerScreen] Deschid Setări — opresc microfonul');
    await _stopListening();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;
    if (!_permissionDenied) {
      AppLogger.i('⚙️ [TunerScreen] Înapoi din Setări — repornesc microfonul');
      _startListening();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_listening && !_permissionDenied) _startListening();
    } else {
      // App în fundal → eliberăm microfonul
      _stopListening();
    }
  }

  Color _colorForCents(double c) {
    // Verde „lipicios" prin histerezis — nu pâlpâie la limita de 5¢
    if (_inTuneHyst) return _green;
    final a = c.abs();
    if (a <= 20) return _orange;
    return _red;
  }

  // Apropie lin valoarea afișată de țintă + avansează respirația.
  // Sare rebuild-ul doar când AMBELE au convers (ac stabil + sinus în
  // platou) — altfel animăm continuu la ~60fps.
  void _onFrame() {
    final target = _hasSignal ? _targetCents.clamp(-50.0, 50.0) : 0.0;
    final targetColor = _hasSignal ? _colorForCents(_targetCents) : _grey;

    final nextCents = _displayCents + (target - _displayCents) * _easing;
    final nextColor =
        Color.lerp(_displayColor, targetColor, _easing) ?? targetColor;

    // Respirație: sinus 0..1 derivat din faza _ticker (perioadă 2.4s)
    final nextBreath = 0.5 + 0.5 * sin(_ticker.value * 2 * pi);

    final centsConverged = (nextCents - _displayCents).abs() < 0.05 &&
        nextColor == _displayColor;
    final breathStill = (nextBreath - _breath).abs() < 0.01;
    if (centsConverged && breathStill) return;

    setState(() {
      _displayCents = nextCents;
      _displayColor = nextColor;
      _breath = nextBreath;
    });
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  void _onValidPitch(double frequency) {
    // În mod manual verificăm strict coarda aleasă; altfel tot acordajul.
    final notes = _lockedString != null ? [_lockedString!] : _tuning.notes;

    // Plierea pe octave folosește o referință de continuitate ca să nu
    // confunde E2 cu E4 când YIN dă eroarea de octavă. Prioritate:
    //   1) hint-ul AI proaspăt (CREPE e robust la octavă) — ground truth
    //   2) mediana valorilor YIN recente — fallback când AI e OFF/expirat
    //   3) 0 → primul cadru, fără context
    final double ref;
    if (_aiHintFresh) {
      ref = _aiFreqHint!;
    } else if (_recentFreqs.isNotEmpty) {
      ref = _median(_recentFreqs);
    } else {
      ref = 0.0;
    }
    final folded = _pitchService.foldToTuning(frequency, notes, ref: ref);

    if (ref > 0) {
      final ratio = folded / ref;
      // Salt mare (~>1 semiton): ori e altă coardă, ori e un cadru de
      // atac haotic. Cerem confirmare pe 2 cadre: respinge zgomotul,
      // dar acceptă rapid schimbarea reală de coardă.
      if (ratio < 0.94 || ratio > 1.06) {
        final p = _pendingFreq;
        if (p != null && (folded / p - 1).abs() < 0.04) {
          // Confirmat → schimbare reală de coardă, reset instant
          _recentFreqs.clear();
          _euro.reset();
          _inTuneHyst = false;
          _tuneCandidate = null;
          _inTuneStreak = 0;
          _pendingFreq = null;
        } else {
          _pendingFreq = folded; // primul cadru „ciudat" → așteptăm
          AppLogger.d('🔍 [Tuner] outlier respins: '
              '${folded.toStringAsFixed(1)}Hz (ref ${ref.toStringAsFixed(1)})');
          return; // NU actualizăm afișajul → fără sărituri haotice
        }
      } else {
        _pendingFreq = null; // în interiorul aceleiași note
      }
    }

    _recentFreqs.add(folded);
    // Mediană scurtă (3) doar ca să taie outlier-ele izolate; netezirea
    // o face filtrul One Euro (adaptiv, fără latență adăugată).
    if (_recentFreqs.length > 3) _recentFreqs.removeAt(0);

    // Nu afișăm pe primul cadru (deseori e atacul): așteptăm 2 valori
    if (_recentFreqs.length < 2) return;

    final medianFreq = _median(_recentFreqs);
    // Filtru adaptiv: lin când coarda susținută e stabilă (gata cu
    // balansul ±8¢ în jurul lui „acordat"), dar rapid când chiar
    // răsucești cheia sau schimbi coarda.
    final smoothFreq = _euro.filter(
      medianFreq,
      DateTime.now().millisecondsSinceEpoch,
    );
    final n = _pitchService.nearestNoteInTuning(smoothFreq, notes);
    AppLogger.d('✅ [Tuner] raw_med=${medianFreq.toStringAsFixed(1)} '
        'smooth=${smoothFreq.toStringAsFixed(1)}Hz '
        '→ ${n.note} ${n.cents.toStringAsFixed(0)}c');

    // ─── AI Precision: YIN conduce, CREPE e referință tăcută ──────
    // YIN driveuiește MEREU acul (real-time, fluid, fără sacadări).
    // CREPE NU atinge acul cât YIN e viu — rolul lui e:
    //   1) referință de octavă pentru folding (aplicat deja mai sus
    //      prin `ref` → ucide confuzia E2↔E4),
    //   2) validare la marcarea „acordat" (mai jos),
    //   3) rescue când YIN moare complet în zgomot (vezi
    //      _rescueMeterWithCrepe, apelat din _fireAiWindow).
    _lastValidDetection = DateTime.now();
    _lastYinAcceptedTime = DateTime.now();
    _restartInactivityTimer();

    // Histerezis: intră în „acordat" sub 5¢, iese abia peste 9¢
    if (!_inTuneHyst && n.cents.abs() < 5) {
      _inTuneHyst = true;
    } else if (_inTuneHyst && n.cents.abs() > 9) {
      _inTuneHyst = false;
    }

    // O coardă se marchează „acordată" doar dacă stă STABIL sub 5¢ pe
    // aceeași notă mai multe cadre la rând (~0.5s). Așa o trecere
    // tranzitorie prin 0 sau o armonică intermitentă (ex. armonica 3 a
    // lui A2 ≈ E4) NU mai marchează fals coarda.
    if (n.note == _tuneCandidate && n.cents.abs() < 5) {
      _inTuneStreak++;
    } else if (n.cents.abs() < 5) {
      _tuneCandidate = n.note;
      _inTuneStreak = 1;
    } else if (n.cents.abs() > 8) {
      _tuneCandidate = null;
      _inTuneStreak = 0;
    }

    // În modul AI Precision marcăm „acordat" doar dacă CREPE confirmă
    // aceeași notă — elimină false-positives pe armonice / zgomot.
    final crepeConfirmsNote = !_aiPrecisionEnabled ||
        !_aiHintFresh ||
        _pitchService.nearestNoteInTuning(_aiFreqHint!, notes).note == n.note;

    if (_inTuneStreak >= _kInTuneFramesNeeded &&
        _tuning.notes.contains(n.note) &&
        !_tunedStrings.contains(n.note) &&
        crepeConfirmsNote) {
      _tunedStrings.add(n.note);
      _playStringTuned(n.note);
      if (_tunedStrings.length == _tuning.notes.length && !_allTuned) {
        _allTuned = true;
        _playAllTuned();
      }
    }

    setState(() {
      _freq = smoothFreq;
      _note = n.note;
      _targetCents = n.cents;
      _hasSignal = true;
    });
  }

  /// CREPE rescuează acul DOAR când YIN a murit în zgomot. Apelată din
  /// _fireAiWindow exclusiv dacă niciun cadru YIN n-a fost acceptat
  /// recent (>700ms). Lag-ul e acceptabil aici (ciclul CREPE ~2s);
  /// easing-ul din _onFrame netezește tranzițiile. Reproduce logica
  /// „acordat" ca să nu inducem regresie pe sesiune (corzi marcate).
  void _rescueMeterWithCrepe(double freq) {
    final notes = _lockedString != null ? [_lockedString!] : _tuning.notes;
    final n = _pitchService.nearestNoteInTuning(freq, notes);

    // Histerezis „acordat"
    if (!_inTuneHyst && n.cents.abs() < 5) {
      _inTuneHyst = true;
    } else if (_inTuneHyst && n.cents.abs() > 9) {
      _inTuneHyst = false;
    }

    // Sustained confirm: o predicție CREPE acoperă ~1.2s de audio, deci
    // valorează cât mai multe cadre YIN. O ponderăm cu 3 → 2 predicții
    // CREPE consecutive sub 5¢ ating pragul _kInTuneFramesNeeded (6).
    if (n.note == _tuneCandidate && n.cents.abs() < 5) {
      _inTuneStreak += 3;
    } else if (n.cents.abs() < 5) {
      _tuneCandidate = n.note;
      _inTuneStreak = 3;
    } else if (n.cents.abs() > 8) {
      _tuneCandidate = null;
      _inTuneStreak = 0;
    }

    if (_inTuneStreak >= _kInTuneFramesNeeded &&
        _tuning.notes.contains(n.note) &&
        !_tunedStrings.contains(n.note)) {
      _tunedStrings.add(n.note);
      _playStringTuned(n.note);
      if (_tunedStrings.length == _tuning.notes.length && !_allTuned) {
        _allTuned = true;
        _playAllTuned();
      }
    }

    _lastValidDetection = DateTime.now();
    _restartInactivityTimer();

    setState(() {
      _freq = freq;
      _note = n.note;
      _targetCents = n.cents;
      _hasSignal = true;
    });
  }

  void _playStringTuned(String note) {
    // Feedback doar haptic — redarea de sunet în timpul capturii
    // microfonului blochează stream-ul de intrare pe Android.
    HapticFeedback.mediumImpact();
    AppLogger.i('✅ [TunerScreen] Coardă acordată: $note '
        '(${_tunedStrings.length}/${_tuning.notes.length})');
  }

  void _playAllTuned() {
    HapticFeedback.heavyImpact();
    AppLogger.i('🎸 [TunerScreen] Toate corzile acordate!');
  }

  void _restartInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityReset, () {
      if (!mounted) return;
      if (_tunedStrings.isNotEmpty || _hasSignal) {
        AppLogger.w('🔶 [TunerScreen] Inactivitate — sesiune resetată automat');
        _resetSession();
      }
    });
  }

  void _resetSession() {
    setState(() {
      _tunedStrings.clear();
      _allTuned = false;
      _recentFreqs.clear();
      _euro.reset();
      _inTuneHyst = false;
      _tuneCandidate = null;
      _inTuneStreak = 0;
      _pendingFreq = null;
      _hasSignal = false;
      _displayCents = 0;
      _displayColor = _grey;
      _lastYinAcceptedTime = null;
    });
  }

  Future<void> _startListening() async {
    if (_listening) return;

    bool permitted = await _audioService.hasPermission();
    if (!permitted) {
      permitted = await _audioService.requestPermission();
    }
    if (!permitted) {
      if (!mounted) return;
      setState(() => _permissionDenied = true);
      return;
    }

    try {
      await _audioService.startRecording();
      if (!mounted) return;

      AppLogger.i('🚀 [TunerScreen] Captură pornită automat');
      _ticker.repeat();
      setState(() {
        _listening = true;
        _permissionDenied = false;
        _recentFreqs.clear();
        _euro.reset();
        _inTuneHyst = false;
        _tuneCandidate = null;
        _inTuneStreak = 0;
        _pendingFreq = null;
        _hasSignal = false;
      });

      _audioSubscription = _audioService.audioStream?.listen((chunk) async {
        // ── Pipeline #1: AI Precision — acumulare ferestre 1.2s ─────
        // Rulează ÎNAINTE de YIN ca să nu pierdem chunk-ul dacă YIN
        // throw-uiește. Nu blochează YIN (fire-and-forget).
        if (_aiPrecisionEnabled) {
          _aiWindowBuffer.add(chunk);
          if (_aiWindowBuffer.length >= _kAiWindowBytes &&
              !_aiRequestInFlight) {
            final window = _aiWindowBuffer.toBytes();
            _aiWindowBuffer.clear();
            // Trimite în background — nu așteptăm aici, YIN continuă
            unawaited(_fireAiWindow(window));
          } else if (_aiWindowBuffer.length >= _kAiWindowBytes * 2) {
            // Backpressure: dacă cererea anterioară încă rulează și
            // s-au strâns deja 2 ferestre, aruncăm cea veche (păstrăm
            // cea proaspătă în buffer pentru următorul ciclu).
            final bytes = _aiWindowBuffer.toBytes();
            _aiWindowBuffer.clear();
            _aiWindowBuffer.add(bytes.sublist(_kAiWindowBytes));
            AppLogger.d('🔍 [Tuner] AI backpressure — am aruncat o fereastră');
          }
        }

        // ── Pipeline #2: YIN — pitch în timp real ───────────────────
        final pr = await _pitchService.analyze(chunk);
        if (!mounted) return;

        // Filtrăm zgomot / voce: doar detecții sigure
        if (!pr.pitched || pr.probability < 0.5 || pr.frequency <= 0) {
          // YIN nu vede pitch. Când AI Precision e ON, CREPE conduce
          // independent acul (_applyCrepeToMeter din _fireAiWindow) —
          // nu facem nimic aici. Dropăm semnalul doar dacă NICIO sursă
          // (YIN sau CREPE) n-a livrat o detecție de _effectiveHold.
          final last = _lastValidDetection;
          if (last == null ||
              DateTime.now().difference(last) > _effectiveHold) {
            if (_hasSignal) {
              _recentFreqs.clear();
              _euro.reset();
              _inTuneHyst = false;
              _tuneCandidate = null;
              _inTuneStreak = 0;
              _pendingFreq = null;
              setState(() => _hasSignal = false);
            }
          }
          return;
        }

        // _lastValidDetection se setează în _onValidPitch DOAR după ce
        // cadrul trece de gating — un cadru YIN respins (zgomot) nu mai
        // ține semnalul „viu" artificial.
        _onValidPitch(pr.frequency);
      });
    } catch (e) {
      AppLogger.e('❌ [TunerScreen] Eroare la pornirea capturii', error: e);
    }
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    try {
      await _audioService.stopRecording();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _inactivityTimer?.cancel();
      _ticker.stop();
      if (!mounted) return;

      AppLogger.w('🔶 [TunerScreen] Captură oprită');
      setState(() {
        _listening = false;
        _hasSignal = false;
        _recentFreqs.clear();
        _euro.reset();
        _inTuneHyst = false;
        _tuneCandidate = null;
        _inTuneStreak = 0;
        _pendingFreq = null;
        _displayCents = 0;
        _displayColor = _grey;
        _lastYinAcceptedTime = null;
      });
    } catch (e) {
      AppLogger.e('❌ [TunerScreen] Eroare la oprirea capturii', error: e);
    }
  }

  void _selectTuning(Tuning tuning) {
    AppLogger.i('🎸 [TunerScreen] Acordaj schimbat: ${tuning.name}');
    setState(() {
      _tuning = tuning;
      _lockedString = null; // acordaj nou → revenim la Auto
      _recentFreqs.clear();
      _euro.reset();
      _inTuneHyst = false;
      _tuneCandidate = null;
      _inTuneStreak = 0;
      _pendingFreq = null;
      _hasSignal = false;
      _lastValidDetection = null;
      _lastYinAcceptedTime = null;
      _tunedStrings.clear();
      _allTuned = false;
    });
  }

  /// Toggle AI Precision: când e ON, fluxul audio comun cu YIN
  /// alimentează un buffer ciclic, iar la fiecare _kAiWindowBytes
  /// trimitem o fereastră la backend pentru predicție CREPE.
  void _toggleAiPrecision() {
    final next = !_aiPrecisionEnabled;
    AppLogger.i('🤖 [TunerScreen] AI Precision → ${next ? 'ON' : 'OFF'}');
    setState(() {
      _aiPrecisionEnabled = next;
      if (!next) _resetAiState();
    });
  }

  void _resetAiState() {
    _aiWindowBuffer.clear();
    _aiFreqHint = null;
    _aiHintTime = null;
    _aiConfidence = 0;
  }

  /// Trimite o fereastră de audio la backend pentru predicție CREPE.
  /// Backpressure strict: un singur request în zbor; dacă vine alt
  /// chunk peste, e aruncat (vezi _onAudioChunk).
  Future<void> _fireAiWindow(Uint8List window) async {
    _aiRequestInFlight = true;
    try {
      final result = await _apiService.detectPitchAI(window);
      if (!mounted || result == null) return;

      // Filtru #1: confidence prea mic → CREPE nu e sigur, ignorăm
      if (result.confidence < _kAiMinConfidence) {
        AppLogger.d('🔍 [Tuner] AI ignorat: conf '
            '${result.confidence.toStringAsFixed(2)}');
        return;
      }

      // Filtru #2: CREPE poate clamp-a la marginile gamei de note (E1..C8).
      // Mapăm pe acordaj — dacă cents iese stuck la ±49.5 e probabil
      // spike, NU folosim ca hint.
      final notes = _lockedString != null ? [_lockedString!] : _tuning.notes;
      final n = _pitchService.nearestNoteInTuning(result.frequency, notes);
      if (n.cents.abs() > _kAiMaxClampedCents) {
        AppLogger.d('🔍 [Tuner] AI spike edge '
            '(${n.cents.toStringAsFixed(0)}c) ignorat');
        return;
      }

      _aiFreqHint = result.frequency;
      _aiHintTime = DateTime.now();
      _aiConfidence = result.confidence;

      // YIN conduce acul cât e viu. CREPE rescuează acul DOAR când YIN
      // a murit (zgomot greu) — altfel CREPE rămâne referință tăcută
      // (octavă + validare), fără să sacadeze linia.
      final yinAlive = _lastYinAcceptedTime != null &&
          DateTime.now().difference(_lastYinAcceptedTime!) <
              const Duration(milliseconds: 700);
      if (yinAlive) {
        // YIN conduce — declanșăm doar un rebuild ușor pentru strip-ul AI
        if (mounted) setState(() {});
      } else {
        _rescueMeterWithCrepe(result.frequency);
      }

      AppLogger.i(
        '🤖 [Tuner] AI hint: ${result.frequency.toStringAsFixed(2)}Hz '
        'conf ${(result.confidence * 100).toStringAsFixed(0)}% '
        '→ ${n.note} ${n.cents.toStringAsFixed(0)}c '
        '(${yinAlive ? "YIN conduce" : "CREPE rescue"})',
      );
    } catch (e, st) {
      AppLogger.e('❌ [Tuner] AI window error', error: e, stackTrace: st);
    } finally {
      _aiRequestInFlight = false;
    }
  }

  /// True cât hint-ul AI mai e proaspăt (folosit ca ref de octavă +
  /// gating YIN + UI).
  bool get _aiHintFresh =>
      _aiPrecisionEnabled &&
      _aiFreqHint != null &&
      _aiHintTime != null &&
      DateTime.now().difference(_aiHintTime!) < _kAiHintFreshness;

  /// Cât rămâne afișată ultima notă după ce sunetul se oprește. În AI
  /// Precision e mai lung decât ciclul CREPE (~2-2.5s) ca să nu pâlpâie
  /// semnalul între două predicții consecutive.
  Duration get _effectiveHold =>
      _aiPrecisionEnabled ? const Duration(seconds: 4) : _holdDuration;

  /// True când AI Precision e ON și YIN nu mai contribuie (zgomot) —
  /// CREPE „cară" singur acul. Driveuiește indicatorul „· AI".
  bool get _aiCarrying =>
      _aiPrecisionEnabled &&
      _hasSignal &&
      (_lastYinAcceptedTime == null ||
          DateTime.now().difference(_lastYinAcceptedTime!) >
              const Duration(milliseconds: 900));

  void _featureSoon(String name) {
    AppLogger.i('🔶 [TunerScreen] „$name" — funcționalitate în curând');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('„$name" — în curând'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  (String, String) _splitNote(String note) {
    final m = RegExp(r'^([A-G]#?)(\d+)$').firstMatch(note);
    if (m == null) return (note, '');
    return (m.group(1)!, m.group(2)!);
  }

  String get _statusText {
    if (_permissionDenied) return 'Acces microfon refuzat';
    if (!_listening) return 'Microfon oprit';
    if (!_hasSignal) return 'Pluck a string to start';
    final c = _targetCents;
    if (c.abs() < 5) return '✓  Acordat';
    return c < 0 ? '▲  Prea jos' : '▼  Prea sus';
  }

  @override
  Widget build(BuildContext context) {
    final (noteName, octave) = _splitNote(_note);
    final showNote = _hasSignal && _note.isNotEmpty;

    return Scaffold(
      backgroundColor: _bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const AppLogoBanner(),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Stack(
        children: [
          const AppBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  // Spațiu pentru AppBar-ul transparent (body extins în
                  // spatele lui ca gradientul să fie continuu).
                  const SizedBox(height: kToolbarHeight),
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildTuningSelector(),
                  const SizedBox(height: 12),
                  _buildModeToggle(),
                  const SizedBox(height: 18),
                  _buildStringRow(),
                  const Spacer(flex: 3),

                  // Panoul central — „instrumentul de măsură"
                  _buildTunerPanel(showNote, noteName, octave),

                  if (_aiPrecisionEnabled) ...[
                    const SizedBox(height: 12),
                    _buildAiStatusStrip(),
                  ],
                  if (_permissionDenied) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _permissionDenied = false);
                        _startListening();
                      },
                      icon: const Icon(Icons.mic),
                      label: const Text('Permite microfonul'),
                    ),
                  ],

                  const Spacer(flex: 3),
                  _buildSessionFooter(),
                  const SizedBox(height: 10),
                  _buildFeatureBar(),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Header: numele instrumentului activ + numărul de corzi. Tap pe tot
  /// rândul → deschide Setări (acolo se schimbă instrumentul). Acordajul
  /// curent e arătat de selectorul de sub el.
  Widget _buildHeader() {
    final inst = AppSettings.instance.instrument;
    return GestureDetector(
      onTap: _openSettings,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(13),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withAlpha(22)),
            ),
            child: Text(inst.emoji, style: const TextStyle(fontSize: 23)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inst.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${inst.stringCount} corzi',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.tune, size: 20, color: Colors.white.withAlpha(120)),
        ],
      ),
    );
  }

  /// Panoul central: nota detectată, frecvența, acul cu cenți și
  /// statusul — grupate într-un card care „prinde viață" în verde când
  /// coarda e acordată (glow + bordură).
  Widget _buildTunerPanel(bool showNote, String noteName, String octave) {
    final showHz = AppSettings.instance.showFrequency;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(7),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _inTuneHyst
              ? _green.withAlpha(130)
              : Colors.white.withAlpha(18),
          width: 1.4,
        ),
        boxShadow: _inTuneHyst
            ? [
                BoxShadow(
                  color: _green.withAlpha(46),
                  blurRadius: 30,
                  spreadRadius: -8,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nota mare — sau placeholder „respirând" când nu e semnal
          SizedBox(
            height: 100,
            child: Center(
              child: showNote
                  ? RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: noteName,
                            style: TextStyle(
                              fontSize: 92,
                              fontWeight: FontWeight.bold,
                              color: _displayColor,
                              height: 1,
                            ),
                          ),
                          if (octave.isNotEmpty)
                            TextSpan(
                              text: octave,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w500,
                                color: Colors.white38,
                              ),
                            ),
                        ],
                      ),
                    )
                  : _buildIdlePlaceholder(),
            ),
          ),
          // Frecvența (Hz) — opțională (Setări → Afișaj)
          if (showHz)
            SizedBox(
              height: 20,
              child: showNote
                  ? RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white38,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        children: [
                          TextSpan(text: '${_freq.toStringAsFixed(1)} Hz'),
                          if (_aiCarrying)
                            TextSpan(
                              text: '   ·   AI',
                              style: TextStyle(
                                color: _aiPurple.withAlpha(220),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                letterSpacing: 0.6,
                              ),
                            ),
                        ],
                      ),
                    )
                  : null,
            )
          else
            const SizedBox(height: 4),
          const SizedBox(height: 14),

          // Meter — MEREU vizibil (idle = ac centrat, gri)
          SizedBox(
            height: 84,
            width: double.infinity,
            child: CustomPaint(
              painter: _TunerMeterPainter(
                cents: _displayCents,
                color: _displayColor,
                hasSignal: _hasSignal,
                inTune: _inTuneHyst,
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            showNote
                ? '${_targetCents > 0 ? "+" : ""}'
                    '${_targetCents.toStringAsFixed(0)} ¢'
                : '—',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: showNote ? _displayColor : Colors.white24,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: showNote ? _displayColor : Colors.white38,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Placeholder „viu" când nu e semnal: o notă muzicală într-un cerc
  /// care respiră lin (oscilatorul _breath), în loc de o liniuță seacă.
  Widget _buildIdlePlaceholder() {
    final scale = 0.92 + 0.08 * _breath;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 94,
        height: 94,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withAlpha((5 + 8 * _breath).round()),
          border: Border.all(
            color: Colors.white.withAlpha((12 + 20 * _breath).round()),
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.music_note,
          size: 44,
          color: Colors.white.withAlpha((26 + 34 * _breath).round()),
        ),
      ),
    );
  }

  /// Strip sub meter: arată că AI Precision lucrează în background.
  /// Bulina pulsează CONTINUU (oscilatorul _breath) cât modul e ON;
  /// afișează ultima frecvență CREPE + confidence ca repere de încredere.
  Widget _buildAiStatusStrip() {
    final hz = _aiFreqHint;
    final conf = _aiConfidence;
    final fresh = _aiHintFresh;
    // Bulina + glow respiră continuu; mai vie când hint-ul e proaspăt.
    final pulse = fresh ? _breath : _breath * 0.4;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _aiCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _aiPurple.withAlpha((55 + 110 * pulse).round()),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _aiPurple.withAlpha((90 + 165 * pulse).round()),
              boxShadow: [
                BoxShadow(
                  color: _aiPurple.withAlpha((30 + 110 * pulse).round()),
                  blurRadius: 3 + 9 * pulse,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.auto_awesome, color: _aiPurple, size: 16),
          const SizedBox(width: 6),
          const Text(
            'AI Precision',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            hz != null ? '${hz.toStringAsFixed(1)} Hz' : 'analizez…',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (hz != null) ...[
            const SizedBox(width: 10),
            Text(
              '${(conf * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: conf > 0.7 ? _aiPurple : Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionFooter() {
    if (_allTuned) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: _green.withAlpha(38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _green),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration, color: _green, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Toate corzile acordate!',
              style: TextStyle(
                color: _green,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _resetSession,
              child: const Text(
                'Reia',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_tunedStrings.isNotEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${_tunedStrings.length}/${_tuning.notes.length} corzi acordate',
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(width: 14),
          OutlinedButton.icon(
            onPressed: _resetSession,
            icon: const Icon(Icons.refresh, size: 16),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white60,
              side: const BorderSide(color: _track),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            label: const Text('Reset sesiune'),
          ),
        ],
      );
    }

    return const SizedBox(height: 36);
  }

  Widget _buildTuningSelector() {
    return Row(
      children: AppSettings.instance.instrument.tunings.map((t) {
        final active = t.name == _tuning.name;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => _selectTuning(t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? _green : _track,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? Colors.black : Colors.white60,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _clearDetection() {
    _recentFreqs.clear();
    _euro.reset();
    _inTuneHyst = false;
    _tuneCandidate = null;
    _inTuneStreak = 0;
    _pendingFreq = null;
    _hasSignal = false;
  }

  void _lockString(String full) {
    AppLogger.i('🎸 [TunerScreen] Mod manual: coarda $full');
    setState(() {
      _lockedString = full;
      _clearDetection();
    });
  }

  void _setAuto() {
    AppLogger.i('🎸 [TunerScreen] Mod Auto (detecție automată)');
    setState(() {
      _lockedString = null;
      _clearDetection();
    });
  }

  // Bara cu modurile: Auto / Manual (stânga) + AI Precision (dreapta).
  // Auto = detectează coarda singur; tap pe o coardă (rândul de jos) =
  // mod manual pe acea coardă. AI Precision = activează refinarea CREPE
  // continuă în paralel cu YIN.
  Widget _buildModeToggle() {
    final auto = _lockedString == null;
    final aiOn = _aiPrecisionEnabled;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pill „Auto" — verde activ, gri când în mod manual
        GestureDetector(
          onTap: auto ? null : _setAuto,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: auto ? _green : _track,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icons.search e mai sugestiv decât autorenew pentru
                // „caută automat coarda" (target/scan)
                Icon(Icons.search,
                    size: 15, color: auto ? Colors.black : Colors.white60),
                const SizedBox(width: 5),
                Text(
                  auto
                      ? 'Auto'
                      : 'Manual: ${_splitNote(_lockedString!).$1}'
                          '${_splitNote(_lockedString!).$2}',
                  style: TextStyle(
                    color: auto ? Colors.black : Colors.white60,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Pill „AI Precision" — purple când ON, gri când OFF
        GestureDetector(
          onTap: _toggleAiPrecision,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: aiOn ? _aiPurple : _track,
              borderRadius: BorderRadius.circular(20),
              boxShadow: aiOn && _aiHintFresh
                  ? [BoxShadow(color: _aiPurple.withAlpha(120), blurRadius: 10)]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: aiOn ? Colors.white : Colors.white60,
                ),
                const SizedBox(width: 5),
                Text(
                  'AI Precision',
                  style: TextStyle(
                    color: aiOn ? Colors.white : Colors.white60,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Cele 6 corzi. Tap = blochează pe acea coardă (mod manual); tap din
  // nou pe ea = revine la Auto. Verde fix dacă acordată în sesiune.
  Widget _buildStringRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(_tuning.notes.length, (i) {
        final full = _tuning.notes[i];
        final (name, _) = _splitNote(full);
        final tuned = _tunedStrings.contains(full);
        final active = _hasSignal && full == _note;
        final locked = _lockedString == full;

        final Color borderColor;
        final Color textColor;
        final Color fill;
        if (locked) {
          borderColor = Colors.white;
          textColor = Colors.white;
          fill = Colors.white.withAlpha(28);
        } else if (tuned) {
          borderColor = _green;
          textColor = _green;
          fill = _green.withAlpha(38);
        } else if (active) {
          borderColor = _displayColor;
          textColor = _displayColor;
          fill = _displayColor.withAlpha(30);
        } else {
          borderColor = _track;
          textColor = Colors.white38;
          fill = Colors.transparent;
        }

        return GestureDetector(
          onTap: () => locked ? _setAuto() : _lockString(full),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(
                color: borderColor,
                width: (locked || tuned || active) ? 2 : 1,
              ),
            ),
            child: tuned && !locked
                ? const Icon(Icons.check, color: _green, size: 18)
                : Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
          ),
        );
      }),
    );
  }

  // Bara cu funcționalitățile aplicației (roadmap), cu efect de sticlă
  // (glassmorphism): BackdropFilter estompează fundalul cu glow-uri de
  // dedesubt. „Acordor" e activ; „Setări" e doar în AppBar (nu dublăm).
  Widget _buildFeatureBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(13),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(28)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _featureItem(Icons.graphic_eq, 'Acordor', active: true),
              _featureItem(
                Icons.av_timer,
                'Metronom',
                onTap: () => _featureSoon('Metronom'),
              ),
              _featureItem(
                Icons.library_music,
                'Acorduri',
                onTap: () => _featureSoon('Acorduri'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureItem(
    IconData icon,
    String label, {
    bool active = false,
    VoidCallback? onTap,
  }) {
    final color = active ? _green : Colors.white54;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TunerMeterPainter extends CustomPainter {
  _TunerMeterPainter({
    required this.cents,
    required this.color,
    required this.hasSignal,
    required this.inTune,
  });

  final double cents;
  final Color color;
  final bool hasSignal;
  final bool inTune;

  static const double _margin = 26;

  double _mapX(double c, double w) {
    final left = _margin;
    final right = w - _margin;
    return left + ((c.clamp(-50.0, 50.0) + 50) / 100) * (right - left);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;

    final trackRect = RRect.fromLTRBR(
      _margin,
      cy - 5,
      w - _margin,
      cy + 5,
      const Radius.circular(5),
    );
    canvas.drawRRect(trackRect, Paint()..color = _track);

    // Zona „acordat" (±5¢) — verde translucid
    final zone = RRect.fromLTRBR(
      _mapX(-5, w),
      cy - 5,
      _mapX(5, w),
      cy + 5,
      const Radius.circular(5),
    );
    canvas.drawRRect(
      zone,
      Paint()..color = _green.withAlpha(hasSignal ? 55 : 28),
    );

    // Repere: minore din 10 în 10, majore la -50/0/+50
    for (int c = -50; c <= 50; c += 10) {
      final x = _mapX(c.toDouble(), w);
      final major = c == 0 || c == -50 || c == 50;
      final h = major ? 16.0 : 8.0;
      final paint = Paint()
        ..color = major ? Colors.white54 : _grey
        ..strokeWidth = major ? 2 : 1;
      canvas.drawLine(Offset(x, cy - 12 - h), Offset(x, cy - 12), paint);
    }

    _drawLabel(canvas, '♭', _mapX(-50, w), cy + 22, Colors.white38);
    _drawLabel(canvas, '0', _mapX(0, w), cy + 22, Colors.white54);
    _drawLabel(canvas, '♯', _mapX(50, w), cy + 22, Colors.white38);

    // Indicatorul
    final px = _mapX(hasSignal ? cents : 0, w);
    final pointerColor = hasSignal ? color : _grey;

    if (hasSignal) {
      final glow = Paint()
        ..color = pointerColor.withAlpha(inTune ? 130 : 70)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, inTune ? 16 : 9);
      canvas.drawCircle(Offset(px, cy), 16, glow);
    }

    final pointer = RRect.fromLTRBR(
      px - 3,
      cy - 26,
      px + 3,
      cy + 26,
      const Radius.circular(3),
    );
    canvas.drawRRect(pointer, Paint()..color = pointerColor);
    canvas.drawCircle(Offset(px, cy), 6, Paint()..color = pointerColor);
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    double x,
    double y,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(_TunerMeterPainter oldDelegate) {
    return oldDelegate.cents != cents ||
        oldDelegate.color != color ||
        oldDelegate.hasSignal != hasSignal ||
        oldDelegate.inTune != inTune;
  }
}
