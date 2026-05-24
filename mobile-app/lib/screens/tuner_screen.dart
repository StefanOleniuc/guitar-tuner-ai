import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tuning.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../services/active_page.dart';
import '../services/note_audio.dart';
import '../services/pitch_service.dart';
import '../services/user_data_service.dart';
import '../utils/app_logger.dart';
import '../utils/one_euro_filter.dart';
import '../widgets/app_dialog.dart';
import '../widgets/brand_app_bar.dart';
import '../widgets/persistent_feature_bar.dart';
import 'auth_screen.dart';
import 'settings_screen.dart';

const Color _green = Color(0xFF00E676);
const Color _orange = Color(0xFFFF9800);
const Color _red = Color(0xFFF44336);
const Color _grey = Color(0xFF424242);
const Color _track = Color(0xFF2A2A2A);
// Paletă pentru verificarea AI (CREPE) — distinctă de verde/roșu YIN
const Color _aiPurple = Color(0xFF9C27B0);
const Color _aiCardBg = Color(0xFF1A0E2E);

// Cât de „lipicios" e indicatorul: fracția cu care se apropie de țintă la
// fiecare cadru (~60fps). Mai mare = mai responsiv (acul prinde mai repede
// mișcarea cheiței), mai jos = mai smooth dar perceptibil ca lag. 0.40
// e ales ca să rămână smooth fără jitter, dar să răspundă rapid (~3 cadre
// pentru ~85% din distanță = ~50ms vs ~80ms la 0.26).
const double _easing = 0.40;

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
  // null = mod Auto; altfel coarda fixată manual.
  String? _lockedString;
  bool _listening = false;
  bool _permissionDenied = false;
  // false cât verificăm permisiunea la pornire.
  bool _permissionChecked = false;
  String _note = '';
  double _freq = 0;
  bool _hasSignal = false;

  // Valoarea măsurată (țintă) vs. valoarea afișată (interpolată lin).
  double _targetCents = 0;
  double _displayCents = 0;
  Color _displayColor = _grey;
  // Oscilator de respirație 0..1 — animă placeholder-ul idle și strip-ul AI.
  double _breath = 0;

  // Sesiune: corzile acordate rămân verzi până la reset
  final Set<String> _tunedStrings = {};
  // Corzi ce tocmai au primit bifa — fereastra de bloom (~480ms).
  final Set<String> _justTuned = {};
  bool _allTuned = false;
  // Mod cromatic: citit din AppSettings (toggle în Setări → Acordor).
  // Când e on, detectăm ORICE notă din lista 84-multi-octavă în loc de
  // doar corzile acordajului ales. UI-ul tuner-ului ascunde string-row +
  // tuning-selector.
  bool get _chromaticMode => AppSettings.instance.chromaticMode;

  // Lista cromatică pre-calculată: C1 .. B7 = 84 note. Costul nearestNote
  // pe lista asta e neglijabil (84 freq compares, < 0.1ms).
  static final List<String> _chromaticNotes = () {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final out = <String>[];
    for (int oct = 1; oct <= 7; oct++) {
      for (final n in names) {
        out.add('$n$oct');
      }
    }
    return List<String>.unmodifiable(out);
  }();
  // Timpul când userul a acordat prima coardă din sesiunea curentă —
  // folosit ca să calculăm durata sesiunii când se completează (istoric).
  DateTime? _sessionStartedAt;
  // Evităm dublarea înregistrării când `_allTuned` rămâne `true` pe
  // mai multe cadre. Resetat la `_resetSession` / `_clearDetection`.
  bool _sessionRecorded = false;

  final List<double> _recentFreqs = [];
  // Filtru adaptiv pe frecvență — elimină jitter-ul când e stabil
  final OneEuroFilter _euro = OneEuroFilter();
  // Histerezis „acordat": intră la 5¢, iese la 9¢ — evită pâlpâitul.
  bool _inTuneHyst = false;
  // Confirmare susținută: 6 cadre YIN sub 5¢ = coardă acordată (~0.5s).
  // Când CREPE conduce (`_aiDriving`), cadrele vin mai rar (~1.2-1.7s pe
  // request); cerem doar 2 → ~2-3s, altfel n-am marca niciodată verde
  // într-un mediu zgomotos.
  static const int _kInTuneFramesNeeded = 6;
  static const int _kInTuneFramesNeededAi = 2;
  String? _tuneCandidate;
  int _inTuneStreak = 0;
  // Salt mare neconfirmat — îl reținem ca să cerem confirmare pe 3 cadre
  // consecutive cu valoare similară şi plauzibilă (aproape de vreo coardă).
  // 3 cadre la ~64ms = ~190ms latenţă la schimbare reală de coardă — dar
  // elimină cazurile în care 2 erori YIN consecutive (ex. subharmonică /4 pe
  // corzi groase) erau acceptate fals şi „lipeau” acul minute întregi.
  double? _pendingFreq;
  int _pendingCount = 0;
  StreamSubscription<Uint8List>? _audioSubscription;

  // ─── AI Precision (CREPE) ─────────────────────────────────────────
  // CREPE rulează pe server (round-trip ~1s) — NU conduce acul în timp
  // real. YIN e master; CREPE = readout separat + fallback când YIN e mut.
  bool _aiPrecisionEnabled = false;
  final BytesBuilder _aiWindowBuffer = BytesBuilder(copy: false);
  bool _aiRequestInFlight = false;
  double? _aiFreqHint;
  DateTime? _aiHintTime;
  double _aiConfidence = 0;
  String _aiNote = '';
  double _aiCents = 0;
  // Eșecuri consecutive de rețea — după _kAiMaxFails oprim AI Precision.
  int _aiFailCount = 0;
  static const int _kAiMaxFails = 3;
  // _aiDriving = CREPE conduce acul (YIN mut). Revenire cu hysteresis.
  bool _aiDriving = false;
  DateTime? _lastYinDisplay;
  int _yinRecoveryCount = 0;
  static const Duration _kYinMuteForAi = Duration(milliseconds: 700);
  static const int _kYinRecoveryFrames = 4;
  // Fereastra trimisă la backend: 0.8s @ 16kHz mono PCM16 = 25600 bytes.
  // Scurtată de la 1.2s ca să simțim CREPE mai puțin „rar" în UI (request
  // mai dese). CREPE rămâne robust pe 800ms (80 predicții la 10ms).
  static const int _kAiSampleRate = 16000;
  static const int _kAiWindowMs = 800;
  static const int _kAiWindowBytes = _kAiWindowMs * _kAiSampleRate * 2 ~/ 1000;
  // Cât rămâne „proaspăt" un hint AI pentru afișaj.
  static const Duration _kAiHintFreshness = Duration(milliseconds: 3500);
  // Prag RMS sub care considerăm fereastra audio „liniște" — sub el NU
  // trimitem nimic la CREPE. Evită ca AI să sugereze frecvențe absurde
  // din zgomotul de fond (de ex. la E4 vs YIN diferență mare în liniște).
  // Valoarea e raportată la maxul int16 (32768). 0.012 ≈ -38dBFS.
  static const double _kAiMinRms = 0.012;
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
    // Bara persistentă pornește deja ascunsă (`ActivePage.barAllowed`
    // default `false`); o pornim când confirmăm permisiunea în `_bootstrap`.
    // Instrument + calibrare A4 din preferințe (deja încărcate în main)
    _tuning = AppSettings.instance.instrument.tunings.first;
    _pitchService.a4 = AppSettings.instance.a4;
    AppSettings.instance.addListener(_onSettingsChanged);
    // Ascultăm tab-ul activ din shell — pornim/oprim microfonul cu el.
    ActivePage.instance.addListener(_onActivePageChanged);
    // 2.4s/ciclu — viteza oscilatorului de respirație pentru placeholder + AI.
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addListener(_onFrame);
    // La pornire verificăm permisiunea ÎNAINTE de a porni captura.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// Verifică statusul permisiunii fără a deschide dialogul de sistem.
  /// Dialogul apare abia când userul apasă butonul de pe ecranul dedicat.
  Future<void> _bootstrap() async {
    final granted = await _audioService.hasPermission();
    if (!mounted) return;

    // Cazul „prima pornire, mic aprobat, fără cont": vrem să-i arătăm
    // AuthScreen-ul fără să apară NICIUN cadru de tuner sub el (altfel
    // se vede UI-ul tunerului în spatele animației de slide-up a rutei
    // — flash vizibil, dă impresia de bug).
    //
    // Soluția: NU ridicăm `_permissionChecked=true` (corpul rămâne
    // SizedBox.shrink, lăsând să se vadă doar AppBackground din MainShell)
    // și `await`-uim push-ul. Când userul revine din AuthScreen, abia
    // atunci materializăm tunerul + pornim captura. Ruta de Auth e
    // pushedover-MainShell oricum, deci bara de jos e ascunsă automat.
    final showWelcome =
        granted &&
        !AppSettings.instance.welcomeSeen &&
        !AuthService.instance.isAuthenticated;
    if (showWelcome) {
      AppSettings.instance.markWelcomeSeen();
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AuthScreen()));
      if (!mounted) return;
    }

    setState(() {
      _permissionChecked = true;
      _permissionDenied = !granted;
    });
    ActivePage.instance.markBootstrapDone();
    ActivePage.instance.setBarAllowed(granted);
    if (!granted) return;
    _startListening();
  }

  // `_maybeShowWelcomeAuth` a fost absorbit în `_bootstrap` ca să putem
  // `await` push-ul și să evităm flash-ul de tuner sub AuthScreen.

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ActivePage.instance.removeListener(_onActivePageChanged);
    AppSettings.instance.removeListener(_onSettingsChanged);
    _inactivityTimer?.cancel();
    _ticker.dispose();
    _audioSubscription?.cancel();
    _audioService.dispose();
    super.dispose();
  }

  // ─── Vizibilitate: microfonul rulează DOAR cât tabul Acordor e vizibil ──
  //
  // `ActivePage` ne spune ce tab e vizibil userului. Când swipe-ăm spre
  // Metronom sau când se deschide o rută peste shell (Setări / Auth),
  // `visibleIndex` nu mai e `tunerIndex` → eliberăm microfonul. La revenire,
  // pornim înapoi captura. Înlocuiește vechiul `RouteAware` (nu mai
  // funcționează din PageView, fiindcă Tuner nu mai are propria PageRoute).
  void _onActivePageChanged() {
    if (!mounted) return;
    if (!_permissionChecked || _permissionDenied) return;
    final isVisible = ActivePage.instance.visibleIndex == ActivePage.tunerIndex;
    if (isVisible && !_listening) {
      AppLogger.i('🚀 [TunerScreen] Tab Acordor vizibil — pornesc microfonul');
      _startListening();
    } else if (!isVisible && _listening) {
      AppLogger.i('🔶 [TunerScreen] Tab Acordor ascuns — opresc microfonul');
      _stopListening();
    }
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
      });
    } else {
      // Doar A4 s-a schimbat → recalculăm afișajul cu noua referință
      setState(() {});
    }
  }

  /// Deschide Setările. Microfonul se oprește/repornește automat prin
  /// `MainShell` — când Setările sunt pushed, shell-ul iese din prim-plan
  /// și `ActivePage.visibleIndex` devine null → `_onActivePageChanged`
  /// oprește captura. La închiderea Setărilor, captura repornește.
  void _openSettings() {
    AppLogger.i('⚙️ [TunerScreen] Deschid Setări');
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Repornim microfonul DOAR dacă tabul Acordor e vizibil (utilizatorul
      // poate fi pe Metronom sau în Setări — atunci NU vrem captură).
      final isTunerVisible =
          ActivePage.instance.visibleIndex == ActivePage.tunerIndex;
      if (isTunerVisible &&
          _permissionChecked &&
          !_permissionDenied &&
          !_listening) {
        _startListening();
      }
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

  // Avansează la fiecare cadru (~60fps): easing ac + respirație.
  // Folosește AnimatedBuilder izolat — evită redesenarea întregului ecran.
  void _onFrame() {
    final target = _hasSignal ? _targetCents.clamp(-50.0, 50.0) : 0.0;
    final targetColor = _hasSignal ? _colorForCents(_targetCents) : _grey;

    final nextCents = _displayCents + (target - _displayCents) * _easing;
    final nextColor =
        Color.lerp(_displayColor, targetColor, _easing) ?? targetColor;
    // Respirație: sinus 0..1 derivat din faza _ticker (perioadă 2.4s)
    final nextBreath = 0.5 + 0.5 * sin(_ticker.value * 2 * pi);

    final centsConverged =
        (nextCents - _displayCents).abs() < 0.05 && nextColor == _displayColor;
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

  /// RMS-ul ferestrei PCM16 mono, normalizat în [0, 1] (raportat la 32768).
  /// Folosit ca să detectăm „liniștea" — dacă RMS sub `_kAiMinRms`, NU
  /// trimitem fereastra la CREPE (ar inventa o frecvență din zgomot).
  static double _audioRms(Uint8List pcm16) {
    if (pcm16.length < 2) return 0;
    final int16 = Int16List.view(
      pcm16.buffer,
      pcm16.offsetInBytes,
      pcm16.lengthInBytes ~/ 2,
    );
    var sumSq = 0.0;
    for (final s in int16) {
      final v = s / 32768.0;
      sumSq += v * v;
    }
    return sqrt(sumSq / int16.length);
  }

  void _onValidPitch(double frequency) {
    // În mod cromatic: detectăm orice notă (84 multi-octavă).
    // În mod manual: doar coarda aleasă. Altfel: toate corzile acordajului.
    final notes = _chromaticMode
        ? _chromaticNotes
        : (_lockedString != null ? [_lockedString!] : _tuning.notes);

    final ref = _recentFreqs.isNotEmpty ? _median(_recentFreqs) : 0.0;
    final folded = _pitchService.foldToTuning(frequency, notes, ref: ref);

    // Plausibility gate: dacă nici după pliere frecvența nu cade la ±200¢
    // (un ton întreg) de vreo coardă, e zgomot/armonică neidentificată
    // (ex. 1469Hz pe E4, 4054Hz pe B3 — la >2000¢ de orice coardă; ar fi
    // clampate la ±50¢ și ar minți utilizatorul). Lăsăm ±200¢ ca să acceptăm
    // strune real-dezacordate până la 2 semitoane — altfel utilizatorul cu
    // chitara puternic dezacordată n-ar vedea nimic pe meter.
    // NU afișăm frame-ul și nu-l băgăm în istoric.
    if (!_pitchService.isPlausibleForTuning(folded, notes, maxCents: 200)) {
      AppLogger.d(
        '🔍 [Tuner] frame implauzibil ignorat: '
        '${folded.toStringAsFixed(1)}Hz (raw ${frequency.toStringAsFixed(1)})',
      );
      return;
    }

    if (ref > 0) {
      final ratio = folded / ref;
      // Salt mare (~>1 semiton): cerem confirmare pe 3 cadre consecutive
      // cu valoare similară. Înainte erau 2 → 2 erori YIN de subharmonică
      // consecutive (ex. 36Hz pe D3) treceau drept „schimbare reală" și
      // lipeau acul la octava greșită minute întregi.
      if (ratio < 0.94 || ratio > 1.06) {
        final p = _pendingFreq;
        if (p != null && (folded / p - 1).abs() < 0.04) {
          _pendingCount++;
          if (_pendingCount < 3) {
            _pendingFreq = folded;
            AppLogger.d(
              '🔍 [Tuner] outlier în așteptare ($_pendingCount/3): '
              '${folded.toStringAsFixed(1)}Hz (ref ${ref.toStringAsFixed(1)})',
            );
            return;
          }
          // 3 cadre la fel → schimbare reală de coardă, reset instant
          _recentFreqs.clear();
          _euro.reset();
          _inTuneHyst = false;
          _tuneCandidate = null;
          _inTuneStreak = 0;
          _pendingFreq = null;
          _pendingCount = 0;
        } else {
          _pendingFreq = folded; // primul cadru ciudat (sau nepotrivit) → reset
          _pendingCount = 1;
          AppLogger.d(
            '🔍 [Tuner] outlier respins: '
            '${folded.toStringAsFixed(1)}Hz (ref ${ref.toStringAsFixed(1)})',
          );
          return; // NU actualizăm afișajul → fără sărituri haotice
        }
      } else {
        _pendingFreq = null; // în interiorul aceleiași note
        _pendingCount = 0;
      }
    }

    _recentFreqs.add(folded);
    // Mediană scurtă (3) taie outlierele izolate; netezirea o face OneEuroFilter.
    if (_recentFreqs.length > 3) _recentFreqs.removeAt(0);

    // Nu afișăm pe primul cadru (deseori e atacul): așteptăm 2 valori
    if (_recentFreqs.length < 2) return;

    final medianFreq = _median(_recentFreqs);
    // OneEuroFilter: lin la notă ținută stabil, rapid la schimbare de coardă.
    final smoothFreq = _euro.filter(
      medianFreq,
      DateTime.now().millisecondsSinceEpoch,
    );
    final n = _pitchService.nearestNoteInTuning(smoothFreq, notes);
    AppLogger.d(
      '✅ [Tuner] raw_med=${medianFreq.toStringAsFixed(1)} '
      'smooth=${smoothFreq.toStringAsFixed(1)}Hz '
      '→ ${n.note} ${n.cents.toStringAsFixed(0)}c',
    );

    _lastValidDetection = DateTime.now();
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

    if (_inTuneStreak >= _kInTuneFramesNeeded &&
        _tuning.notes.contains(n.note) &&
        !_tunedStrings.contains(n.note)) {
      // Prima coardă din sesiune → pornim cronometrul pentru istoric.
      _sessionStartedAt ??= DateTime.now();
      _tunedStrings.add(n.note);
      _playStringTuned(n.note);
      if (_tunedStrings.length == _tuning.notes.length && !_allTuned) {
        _allTuned = true;
        _playAllTuned();
        _recordSessionIfEligible();
      }
    }

    _lastYinDisplay = DateTime.now();

    // Revenire din fallback CREPE: numărăm _kYinRecoveryFrames cadre stabile.
    if (_aiDriving) {
      _yinRecoveryCount++;
      if (_yinRecoveryCount < _kYinRecoveryFrames) return;
      _aiDriving = false;
      _yinRecoveryCount = 0;
      AppLogger.i('🎸 [Tuner] YIN stabil — preia acul înapoi de la CREPE');
    }

    setState(() {
      _freq = smoothFreq;
      _note = n.note;
      _targetCents = n.cents;
      _hasSignal = true;
    });
  }

  /// CREPE conduce acul — doar în fallback când YIN e mut.
  ///
  /// Updatează ȘI starea de „coardă acordată" cu un threshold relaxat
  /// (`_kInTuneFramesNeededAi`), pentru că request-urile CREPE vin mai rar
  /// (~1-1.5s) — la threshold-ul YIN (6 cadre) practic n-am marca niciodată
  /// verde într-un mediu zgomotos unde CREPE conduce.
  void _driveMeterFromCrepe() {
    final hz = _aiFreqHint;
    if (hz == null || _aiNote.isEmpty) return;
    _lastValidDetection = DateTime.now(); // ține semnalul „viu"
    // Resetăm și inactivity timer-ul — altfel sesiunea pică la 12s chiar
    // dacă CREPE raportează activ (YIN e mut în zgomot și _onValidPitch
    // nu mai e apelat → timer-ul ar expira mid-tuning și ar șterge corzile
    // deja acordate).
    _restartInactivityTimer();
    if (!mounted) return;

    // Histerezis verde — aceleași praguri ca pe ramura YIN (intră la 5¢,
    // iese la 9¢). Fără asta `_colorForCents` nu devine niciodată verde
    // când CREPE conduce, chiar dacă `_aiCents` e ~0.
    if (!_inTuneHyst && _aiCents.abs() < 5) {
      _inTuneHyst = true;
    } else if (_inTuneHyst && _aiCents.abs() > 9) {
      _inTuneHyst = false;
    }

    setState(() {
      _freq = hz;
      _note = _aiNote;
      _targetCents = _aiCents;
      _hasSignal = true;
    });
    _trackInTune(_aiNote, _aiCents, _kInTuneFramesNeededAi);
  }

  /// State machine pentru marcarea unei corzi ca acordate. Extras din
  /// `_onValidPitch` ca să-l poată reutiliza și `_driveMeterFromCrepe`
  /// cu un threshold diferit (cadrele AI vin mai rar).
  void _trackInTune(String note, double cents, int framesNeeded) {
    if (note == _tuneCandidate && cents.abs() < 5) {
      _inTuneStreak++;
    } else if (cents.abs() < 5) {
      _tuneCandidate = note;
      _inTuneStreak = 1;
    } else if (cents.abs() > 8) {
      _tuneCandidate = null;
      _inTuneStreak = 0;
    }
    if (_inTuneStreak >= framesNeeded &&
        _tuning.notes.contains(note) &&
        !_tunedStrings.contains(note)) {
      _sessionStartedAt ??= DateTime.now();
      _tunedStrings.add(note);
      _playStringTuned(note);
      if (_tunedStrings.length == _tuning.notes.length && !_allTuned) {
        _allTuned = true;
        _playAllTuned();
        _recordSessionIfEligible();
      }
    }
  }

  void _playStringTuned(String note) {
    // Feedback haptic — redarea de sunet în timpul capturii blochează stream-ul pe Android.
    HapticFeedback.mediumImpact();
    // Bloom vizual: AnimatedScale pe cercul din string row face scale-up
    // rapid la 1.35×, revenind la 1.0 după ~480ms.
    setState(() => _justTuned.add(note));
    Future.delayed(const Duration(milliseconds: 480), () {
      if (mounted) setState(() => _justTuned.remove(note));
    });
    AppLogger.i(
      '✅ [TunerScreen] Coardă acordată: $note '
      '(${_tunedStrings.length}/${_tuning.notes.length})',
    );
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

  /// Salvează în istoric sesiunea curentă (doar dacă userul e logat și
  /// nu am salvat-o încă). Fire-and-forget — istoricul cloud nu blochează
  /// niciun flow vizibil userului.
  void _recordSessionIfEligible() {
    if (_sessionRecorded) return;
    final started = _sessionStartedAt;
    if (started == null) return;
    _sessionRecorded = true;
    final duration = DateTime.now().difference(started).inMilliseconds / 1000.0;
    AppLogger.i(
      '📜 [Tuner] Sesiune completă: ${_tuning.notes.length} corzi în ${duration.toStringAsFixed(1)}s',
    );
    UserDataService.instance.recordSession(
      instrument: AppSettings.instance.instrumentId,
      tuningName: _tuning.name,
      stringsTuned: _tunedStrings.length,
      totalStrings: _tuning.notes.length,
      durationSeconds: duration,
      a4: AppSettings.instance.a4,
    );
  }

  void _resetSession() {
    _justTuned.clear();
    setState(() {
      _tunedStrings.clear();
      _allTuned = false;
      _sessionStartedAt = null;
      _sessionRecorded = false;
      _recentFreqs.clear();
      _euro.reset();
      _inTuneHyst = false;
      _tuneCandidate = null;
      _inTuneStreak = 0;
      _pendingFreq = null;
      _hasSignal = false;
      _displayCents = 0;
      _displayColor = _grey;
      _aiDriving = false;
      _yinRecoveryCount = 0;
      _lastYinDisplay = null;
    });
  }

  Future<void> _startListening() async {
    if (_listening) return;

    // Nu cerem permisiunea aici — o face ecranul dedicat.
    final permitted = await _audioService.hasPermission();
    if (!permitted) {
      if (!mounted) return;
      setState(() {
        _permissionChecked = true;
        _permissionDenied = true;
      });
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
        // ── Pipeline #1: AI Precision — acumulare ferestre 0.8s ─────
        if (_aiPrecisionEnabled) {
          _aiWindowBuffer.add(chunk);
          if (_aiWindowBuffer.length >= _kAiWindowBytes &&
              !_aiRequestInFlight) {
            final window = _aiWindowBuffer.toBytes();
            _aiWindowBuffer.clear();
            // Skip dacă fereastra e liniște — CREPE nu mai inventează un
            // F# vag din zgomotul de fond și economisim un request.
            if (_audioRms(window) < _kAiMinRms) {
              AppLogger.d(
                '🔍 [Tuner] AI fereastră silențioasă — sar peste request',
              );
            } else {
              // Trimite în background — nu așteptăm aici, YIN continuă.
              unawaited(_fireAiWindow(window));
            }
          } else if (_aiWindowBuffer.length >= _kAiWindowBytes * 2) {
            // Backpressure: cererea anterioară încă rulează, aruncăm fereastra veche.
            final bytes = _aiWindowBuffer.toBytes();
            _aiWindowBuffer.clear();
            _aiWindowBuffer.add(bytes.sublist(_kAiWindowBytes));
            AppLogger.d('🔍 [Tuner] AI backpressure — am aruncat o fereastră');
          }
        }

        // ── Fallback CREPE: YIN mut > 700ms + hint proaspăt → CREPE preia acul.
        if (_aiPrecisionEnabled && !_aiDriving && _aiHintFresh) {
          final lastYin = _lastYinDisplay;
          if (lastYin == null ||
              DateTime.now().difference(lastYin) > _kYinMuteForAi) {
            AppLogger.i('🤖 [Tuner] YIN mut — CREPE preia acul (fallback)');
            _aiDriving = true;
            _yinRecoveryCount = 0;
            _driveMeterFromCrepe(); // arătăm imediat ce avem de la CREPE
          }
        }

        // ── Pipeline #2: YIN — pitch în timp real ───────────────────
        final pr = await _pitchService.analyze(chunk);

        // Filtrăm zgomot: doar detecții sigure
        if (!pr.pitched || pr.probability < 0.5 || pr.frequency <= 0) {
          // Fără pitch — după _holdDuration dropăm semnalul.
          final last = _lastValidDetection;
          if (last == null || DateTime.now().difference(last) > _holdDuration) {
            if (_hasSignal) {
              _recentFreqs.clear();
              _euro.reset();
              _inTuneHyst = false;
              _tuneCandidate = null;
              _inTuneStreak = 0;
              _pendingFreq = null;
              setState(() {
                _hasSignal = false;
                _aiDriving = false;
              });
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
      if (!mounted) return;
      _ticker.stop();

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
        _aiDriving = false;
        _yinRecoveryCount = 0;
        _lastYinDisplay = null;
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
      _tunedStrings.clear();
      _allTuned = false;
      _sessionStartedAt = null;
      _sessionRecorded = false;
    });
  }

  /// Activează/dezactivează AI Precision (CREPE backend).
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
    _aiNote = '';
    _aiCents = 0;
    _aiFailCount = 0;
    _aiDriving = false;
    _yinRecoveryCount = 0;
  }

  /// Trimite o fereastră audio la backend CREPE. Un singur request în zbor.
  Future<void> _fireAiWindow(Uint8List window) async {
    _aiRequestInFlight = true;
    try {
      final result = await _apiService.detectPitchAI(window);
      if (!mounted) return;

      // null → eroare rețea; după _kAiMaxFails eșecuri oprim AI Precision.
      if (result == null) {
        _aiFailCount++;
        if (_aiFailCount >= _kAiMaxFails && _aiPrecisionEnabled) {
          AppLogger.w('🔶 [Tuner] AI Precision oprit — server inaccesibil');
          setState(() {
            _aiPrecisionEnabled = false;
            _resetAiState();
          });
          showAppMessage(
            context,
            icon: Icons.cloud_off_rounded,
            title: 'Conexiune indisponibilă',
            message:
                'AI Precision are nevoie de internet ca să analizeze '
                'sunetul. Am revenit la acordarea clasică — funcționează '
                'perfect și așa.',
            accent: _aiPurple,
          );
        }
        return;
      }
      _aiFailCount = 0; // un răspuns valid → resetăm contorul

      // Filtru #1: confidence prea mic → ignorăm
      if (result.confidence < _kAiMinConfidence) {
        AppLogger.d(
          '🔍 [Tuner] AI ignorat: conf '
          '${result.confidence.toStringAsFixed(2)}',
        );
        return;
      }

      // Filtru #2: spike la marginea gamei CREPE → ignorăm.
      final notes = _chromaticMode
          ? _chromaticNotes
          : (_lockedString != null ? [_lockedString!] : _tuning.notes);
      final n = _pitchService.nearestNoteInTuning(result.frequency, notes);
      if (n.cents.abs() > _kAiMaxClampedCents) {
        AppLogger.d(
          '🔍 [Tuner] AI spike edge '
          '(${n.cents.toStringAsFixed(0)}c) ignorat',
        );
        return;
      }

      if (mounted) {
        setState(() {
          _aiFreqHint = result.frequency;
          _aiHintTime = DateTime.now();
          _aiConfidence = result.confidence;
          _aiNote = n.note;
          _aiCents = n.cents;
        });
      }

      // CREPE conduce acul doar când YIN e mut.
      if (_aiDriving) _driveMeterFromCrepe();

      AppLogger.i(
        '🤖 [Tuner] AI: ${result.frequency.toStringAsFixed(2)}Hz '
        'conf ${(result.confidence * 100).toStringAsFixed(0)}% '
        '→ ${n.note} ${n.cents.toStringAsFixed(0)}c'
        '${_aiDriving ? " (CREPE conduce)" : ""}',
      );
    } catch (e, st) {
      AppLogger.e('❌ [Tuner] AI window error', error: e, stackTrace: st);
    } finally {
      _aiRequestInFlight = false;
    }
  }

  /// True cât hint-ul AI mai e proaspăt — pentru afișajul strip-ului.
  bool get _aiHintFresh =>
      _aiPrecisionEnabled &&
      _aiFreqHint != null &&
      _aiHintTime != null &&
      DateTime.now().difference(_aiHintTime!) < _kAiHintFreshness;

  (String, String) _splitNote(String note) {
    final m = RegExp(r'^([A-G]#?)(\d+)$').firstMatch(note);
    if (m == null) return (note, '');
    return (m.group(1)!, m.group(2)!);
  }

  String get _statusText {
    if (_permissionDenied) return 'Acces microfon refuzat';
    if (!_listening) return 'Microfon oprit';
    if (!_hasSignal) return 'Ciupește o coardă pentru a începe';
    final c = _targetCents;
    if (c.abs() < 5) return '✓  Acordat';
    return c < 0 ? '▲  Prea jos' : '▼  Prea sus';
  }

  @override
  Widget build(BuildContext context) {
    final (noteName, octave) = _splitNote(_note);
    final showNote = _hasSignal && _note.isNotEmpty;

    return Scaffold(
      // Fundal transparent — `MainShell` pictează AppBackground unitar
      // sub PageView (fără cusături la swipe).
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      // AppBar comun (logo + sign-up + setări) — aceleași pentru Acordor și
      // Metronom (vezi `BrandAppBar`). Sărit doar pe ecranul de permisiune.
      appBar: (_permissionChecked && !_permissionDenied)
          ? BrandAppBar(onSettings: _openSettings)
          : null,
      body: Stack(
        children: [
          if (!_permissionChecked)
            // Verificăm permisiunea (instant) — doar fundalul, fără flash
            // de tuner în spatele dialogului de sistem.
            const SizedBox.shrink()
          else if (_permissionDenied)
            _buildPermissionScreen()
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    // Spațiu pentru AppBar-ul transparent (body extins în
                    // spate ca gradientul să fie continuu).
                    const SizedBox(height: kToolbarHeight - 12),
                    // ── Selectorul de MOD principal ─────────────────
                    // Două pastile mari, segmented: Instrument vs Cromatic.
                    // Tot ce e specific instrumentului (acordaj, corzi) se
                    // ascunde automat când treci pe Cromatic — concept fără
                    // sens când detectezi orice notă.
                    _buildModeSwitcher(),
                    const SizedBox(height: 14),
                    if (!_chromaticMode) ...[
                      _buildTuningSelector(),
                      const SizedBox(height: 14),
                    ],
                    _buildModeToggle(),
                    const SizedBox(height: 18),
                    if (!_chromaticMode) _buildStringRow(),
                    const Spacer(flex: 3),

                    // Panoul central — „instrumentul de măsură"
                    _buildTunerPanel(showNote, noteName, octave),

                    if (_aiPrecisionEnabled) ...[
                      const SizedBox(height: 12),
                      _buildAiStatusStrip(),
                    ],

                    const Spacer(flex: 3),
                    _buildSessionFooter(),
                    // Gap explicit între footer și spațiul navbarului —
                    // evită lipirea conținutului de bara plutitoare.
                    const SizedBox(height: 14),
                    // Spațiu rezervat pentru bara persistentă plutitoare —
                    // bara aparține `MainShell`, dar conținutul nostru nu
                    // trebuie să ajungă sub ea.
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

  /// Ecran dedicat când microfonul e refuzat — fără el aplicația nu poate
  /// funcționa, deci blocăm tot până la aprobare. Intră cu o animație
  /// scurtă (fade + slide).
  Widget _buildPermissionScreen() {
    return SafeArea(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 540),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - t)),
            child: child,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 86,
                height: 86,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _green.withAlpha(26),
                  border: Border.all(color: _green.withAlpha(95), width: 1.5),
                ),
                child: const Icon(
                  Icons.mic_none_rounded,
                  color: _green,
                  size: 40,
                ),
              ),
              const SizedBox(height: 28),
              const Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.bold,
                    height: 1.22,
                  ),
                  children: [
                    TextSpan(
                      text: 'Permite accesul la ',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextSpan(
                      text: 'microfon',
                      style: TextStyle(color: _green),
                    ),
                    TextSpan(
                      text: ' ca să continui',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Folosim microfonul telefonului doar pentru a-ți detecta '
                'și acorda corzile — nimic nu e înregistrat sau trimis.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _requestMicAccess,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: const Text(
                  'Permite microfonul',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cere permisiunea de microfon; dacă e refuzată permanent, deschide
  /// setările de sistem (singura cale după un refuz permanent).
  Future<void> _requestMicAccess() async {
    AppLogger.i('🎤 [TunerScreen] Cerere acces microfon din ecranul dedicat');
    final granted = await _audioService.requestPermission();
    if (!mounted) return;
    if (granted) {
      // Welcome auth la prima pornire: așteptăm să se închidă AuthScreen-ul
      // înainte să materializăm tunerul, ca să nu apară flash în spate.
      final showWelcome =
          !AppSettings.instance.welcomeSeen &&
          !AuthService.instance.isAuthenticated;
      if (showWelcome) {
        AppSettings.instance.markWelcomeSeen();
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AuthScreen()));
        if (!mounted) return;
      }
      setState(() => _permissionDenied = false);
      ActivePage.instance.setBarAllowed(true);
      _startListening();
    } else {
      await _audioService.openSystemSettings();
    }
  }

  /// Panoul central: notă, frecvență, ac cu cenți, status acordaj.
  Widget _buildTunerPanel(bool showNote, String noteName, String octave) {
    final showHz = AppSettings.instance.showFrequency;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _inTuneHyst
              ? [const Color(0xFF112018), const Color(0xFF0C150F)]
              : [const Color(0xFF181818), const Color(0xFF0F0F0F)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _inTuneHyst
              ? _green.withAlpha(140)
              : Colors.white.withAlpha(18),
          width: 1.4,
        ),
        boxShadow: _inTuneHyst
            ? [
                BoxShadow(
                  color: _green.withAlpha(55),
                  blurRadius: 40,
                  spreadRadius: -8,
                ),
                BoxShadow(
                  color: _green.withAlpha(20),
                  blurRadius: 80,
                  spreadRadius: -20,
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
          // Frecvența (Hz) — opțională (Setări → Afișaj). Când CREPE
          // conduce acul (fallback în zgomot), marcăm cu „· AI".
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
                          if (_aiDriving)
                            TextSpan(
                              text: '   ·   AI',
                              style: TextStyle(
                                color: _aiPurple.withAlpha(230),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            )
          else
            const SizedBox(height: 4),
          const SizedBox(height: 14),

          // Meter — MEREU vizibil (idle = ac centrat, gri). RepaintBoundary
          // izolează re-pictarea acului de restul arborelui.
          RepaintBoundary(
            child: SizedBox(
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

  /// Placeholder animat când nu e semnal.
  ///
  /// Emblema „GT" (PNG cu fundal transparent, generat din logo-ul oficial)
  /// stă în interiorul cercului verde pulsator. Peste ea, un strat fin de
  /// film grain dă senzația premium / „live", iar fade-ul lin (legat de
  /// `_breath`) face placeholder-ul să respire fără să distragă.
  Widget _buildIdlePlaceholder() {
    final scale = 0.93 + 0.07 * _breath;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              _green.withAlpha((10 + 18 * _breath).round()),
              Colors.transparent,
            ],
          ),
          border: Border.all(
            color: _green.withAlpha((22 + 38 * _breath).round()),
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // Halo radial verde subtil sub emblemă — adâncime fără
              // zgomot vizual.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      _green.withAlpha((26 + 32 * _breath).round()),
                      Colors.transparent,
                    ],
                    radius: 0.85,
                  ),
                ),
              ),
              // Emblema „GT" — padding ca să rămână cercul vizibil în jur.
              // Pulsează cu un fade lin sincronizat cu respirația.
              Padding(
                padding: const EdgeInsets.all(16),
                child: Opacity(
                  opacity: (0.62 + 0.30 * _breath).clamp(0.0, 1.0),
                  child: Image.asset(
                    'assets/images/GTune_emblem_transparent.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              // Film grain — textură fină de zgomot, reseed la fiecare
              // tick de respirație pentru efect „cinematic".
              IgnorePointer(
                child: Opacity(
                  opacity: 0.07 + 0.04 * _breath,
                  child: CustomPaint(
                    painter: _FilmGrainPainter(seed: _breath),
                    size: Size.infinite,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Strip AI (CREPE) sub meter — a doua opinie, independent de acul YIN.
  Widget _buildAiStatusStrip() {
    final fresh = _aiHintFresh;
    final hz = _aiFreqHint;
    final hasReading = hz != null && _aiNote.isNotEmpty;
    // Iconița sparkle pulsează lin cu respirația (mai vie când e proaspăt).
    final pulse = fresh ? _breath : _breath * 0.35;
    final centsTxt = _aiCents == 0
        ? '0¢'
        : '${_aiCents > 0 ? '+' : ''}${_aiCents.toStringAsFixed(0)}¢';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _aiCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _aiPurple.withAlpha((55 + 110 * pulse).round()),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            color: _aiPurple.withAlpha((150 + 105 * pulse).round()),
            size: 17,
          ),
          const SizedBox(width: 7),
          const Text(
            'AI',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (hasReading) ...[
            // Nota AI + cenți
            Text(
              '$_aiNote  $centsTxt',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${hz.toStringAsFixed(1)} Hz',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${(_aiConfidence * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: _aiConfidence > 0.7 ? _aiPurple : Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else
            const Text(
              'analizez…',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionFooter() {
    final Widget content;
    if (_allTuned) {
      content = Container(
        key: const ValueKey('allTuned'),
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
    } else if (_tunedStrings.isNotEmpty) {
      content = Row(
        key: const ValueKey('partial'),
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
    } else {
      content = const SizedBox(key: ValueKey('empty'), height: 36);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        // Scale din topCenter → creșterea merge în sus (spre spacer),
        // nu în jos spre nav bar. Evită suprapunerea indiferent de timing.
        alignment: Alignment.topCenter,
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: content,
    );
  }

  /// Selectorul principal de **mod** al tunerului: două pastile mari,
  /// segmented — "Instrument" (cu emoji + numele instrumentului curent)
  /// vs "Cromatic" (orice notă). Înlocuiește vechiul `_buildHeader`
  /// (card cu instrumentul) și banner-ul vechi din modul cromatic.
  ///
  /// Tap pe pastila Instrument când e deja activă → deschide Setări
  /// (shortcut familiar; păstrăm comportamentul vechi al header-ului).
  Widget _buildModeSwitcher() {
    final inst = AppSettings.instance.instrument;
    final chromatic = _chromaticMode;

    Widget pill({
      required bool active,
      required Widget child,
      required VoidCallback onTap,
      required Color activeBorder,
    }) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withAlpha(22)
                  : Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active
                    ? activeBorder.withAlpha(160)
                    : Colors.white.withAlpha(20),
                width: active ? 1.4 : 1.0,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: activeBorder.withAlpha(40),
                        blurRadius: 18,
                        spreadRadius: -6,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
      );
    }

    return Row(
      children: [
        pill(
          active: !chromatic,
          activeBorder: _green,
          // Când pastila Instrument e deja activă, tap deschide Setări
          // (shortcut: schimbi rapid instrumentul/calibrarea). Dacă vii
          // din Cromatic, tap-ul doar comută înapoi pe instrument.
          onTap: () {
            if (chromatic) {
              AppSettings.instance.setChromaticMode(false);
            } else {
              _openSettings();
            }
          },
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(inst.emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      inst.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: chromatic ? Colors.white54 : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      chromatic ? 'Comută înapoi' : _tuning.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        pill(
          active: chromatic,
          activeBorder: _green,
          onTap: () {
            if (!chromatic) AppSettings.instance.setChromaticMode(true);
          },
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: chromatic
                      ? _green.withAlpha(36)
                      : Colors.white.withAlpha(14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.piano_outlined,
                  size: 20,
                  color: chromatic ? _green : Colors.white60,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Cromatic',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: chromatic ? Colors.white : Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      chromatic ? 'Orice notă' : 'Orice notă muzicală',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
    _lastYinDisplay = null;
    _aiDriving = false;
    _yinRecoveryCount = 0;
  }

  void _lockString(String full) {
    AppLogger.i('🎸 [TunerScreen] Mod manual: coarda $full');
    setState(() {
      _lockedString = full;
      _clearDetection();
    });
    // Sunetul DE REFERINȚĂ blochează AudioRecord pe Android dacă rulează
    // în paralel cu MediaPlayer. Soluție: oprim captura, redăm nota,
    // așteptăm să se termine, repornim — fără chunk-uri pierdute, fără
    // un mic-stream blocat „mut" la final.
    _playReferenceNote(full);
  }

  /// Pauză YIN+CREPE, redă nota timp de ~1.5s, apoi repornește captura.
  Future<void> _playReferenceNote(String full) async {
    final wasListening = _listening;
    if (wasListening) {
      await _stopListening();
    }
    // Curățăm un buffer AI vechi — altfel primul request după restart ar
    // conține audio dinaintea notei de referință.
    _aiWindowBuffer.clear();
    unawaited(NoteAudio.instance.play(full, a4: AppSettings.instance.a4));
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    if (wasListening && _permissionChecked && !_permissionDenied) {
      _startListening();
    }
  }

  void _setAuto() {
    AppLogger.i('🎸 [TunerScreen] Mod Auto (detecție automată)');
    setState(() {
      _lockedString = null;
      _clearDetection();
    });
  }

  // Bara moduri: AUTO + AI Precision, două toggle-uri iOS.
  //
  // În modul cromatic AUTO nu mai are sens (nu există „coardă locked"
  // când detectăm orice notă), așa că rămâne doar AI Precision —
  // centered, ca să nu pară un toggle orfan într-un capăt.
  Widget _buildModeToggle() {
    final auto = _lockedString == null;
    final aiOn = _aiPrecisionEnabled;
    final chromatic = _chromaticMode;

    final autoToggle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => auto ? _lockString(_tuning.notes.first) : _setAuto(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.gps_fixed,
            size: 15,
            color: auto ? _green : Colors.white38,
          ),
          const SizedBox(width: 7),
          Text(
            'AUTO',
            style: TextStyle(
              color: auto ? Colors.white : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 9),
          _IosToggle(value: auto, activeColor: _green),
        ],
      ),
    );

    final aiToggle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleAiPrecision,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 15,
            color: aiOn ? _aiPurple : Colors.white38,
          ),
          const SizedBox(width: 7),
          Text(
            'AI Precision',
            style: TextStyle(
              color: aiOn ? Colors.white : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 9),
          _IosToggle(value: aiOn, activeColor: _aiPurple, glow: true),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: chromatic
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceEvenly,
      children: chromatic ? [aiToggle] : [autoToggle, aiToggle],
    );
  }

  // Cele 6 corzi — tap blochează/deblochează coarda. Verde = acordată.
  // În modul stângaci ordinea e oglindită (coarda joasă în dreapta).
  Widget _buildStringRow() {
    final notes = AppSettings.instance.leftHanded
        ? _tuning.notes.reversed.toList(growable: false)
        : _tuning.notes;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(notes.length, (i) {
        final full = notes[i];
        final (name, _) = _splitNote(full);
        final tuned = _tunedStrings.contains(full);
        final active = _hasSignal && full == _note;
        final locked = _lockedString == full;

        final bool justTuned = _justTuned.contains(full);
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
          fill = justTuned ? _green.withAlpha(90) : _green.withAlpha(38);
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
          child: AnimatedScale(
            scale: justTuned ? 1.35 : 1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
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
          ),
        );
      }),
    );
  }

  // Bara persistentă cu „Acordor / Metronom / Cont" e găzduită acum de
  // `MainShell` (vezi `PersistentFeatureBar`) — Tuner doar rezervă spațiu
  // jos pentru ea.
}

/// Comutator stil iOS — pistă rotunjită + bilă animată. Glow opțional.
class _IosToggle extends StatelessWidget {
  const _IosToggle({
    required this.value,
    required this.activeColor,
    this.glow = false,
  });

  final bool value;
  final Color activeColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: 46,
      height: 27,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: value ? activeColor : const Color(0xFF2E2E2E),
        boxShadow: value && glow
            ? [
                BoxShadow(
                  color: activeColor.withAlpha(150),
                  blurRadius: 12,
                  spreadRadius: -1,
                ),
              ]
            : null,
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 21,
          height: 21,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
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

    // Zona „acordat" (±5¢)
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

    // Indicator
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

  void _drawLabel(Canvas canvas, String text, double x, double y, Color color) {
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

/// Strat de film grain (zgomot fin alb pe transparent) folosit ca overlay
/// peste emblema din placeholder-ul idle. Reseed-ul la fiecare cadru, prin
/// modificarea `seed`-ului din `_breath`, dă senzația vizuală de „live" —
/// fără să distragă, dar perceptibil ca textură premium.
class _FilmGrainPainter extends CustomPainter {
  _FilmGrainPainter({required this.seed});

  final double seed;

  @override
  void paint(Canvas canvas, Size size) {
    // Densitate moderată: ~3% pixeli pictați la o regiune de 96×96 = ~280
    // de puncte. Suficient pentru textură, ieftin pentru repaint la 60 fps.
    final rng = Random((seed * 100000).round());
    final count = (size.width * size.height * 0.035).round();
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      // Mix alb / verde-neon foarte subtil, ca grain-ul să se integreze cu
      // paleta brandului în loc să arate ca „static TV".
      final useGreen = rng.nextInt(7) == 0;
      paint.color = useGreen
          ? const Color(0xFF00E676).withAlpha(40 + rng.nextInt(70))
          : Colors.white.withAlpha(25 + rng.nextInt(90));
      canvas.drawCircle(Offset(dx, dy), 0.45, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FilmGrainPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
