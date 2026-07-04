import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../utils/app_logger.dart';

/// Motor metronom: programare precisă fără drift + click audio generat în memorie.
class MetronomeEngine {
  final AudioPlayer _accentPlayer = AudioPlayer();
  final AudioPlayer _normalPlayer = AudioPlayer();

  late final Uint8List _accentWav;
  late final Uint8List _normalWav;

  Timer? _timer;
  DateTime _nextBeat = DateTime.now();
  int _beat = 0;
  bool _running = false;
  bool _ready = false;

  /// Tempo (bătăi pe minut). Modificabil și în timp ce rulează.
  int bpm = 100;

  /// Bătăi pe măsură (prima e accentuată).
  int beatsPerBar = 4;

  /// Apelat la fiecare bătaie — `beatInBar` 0-based, `accent` = bătaia 1.
  void Function(int beatInBar, bool accent)? onBeat;

  bool get isRunning => _running;

  /// Generează click-urile și pregătește playerele. De apelat o dată.
  Future<void> init() async {
    // Frecvențe ascuțite ca metronoamele clasice (preferința userului),
    // dar cu atac de 4ms în `_clickWav` ca să elimine pop-ul transient
    // și să sune un pic mai curat.
    _accentWav = _clickWav(freq: 2000, durationMs: 60, volume: 0.95);
    _normalWav = _clickWav(freq: 1250, durationMs: 45, volume: 0.62);
    try {
      for (final p in [_accentPlayer, _normalPlayer]) {
        await p.setReleaseMode(ReleaseMode.stop);
      }
      _ready = true;
      AppLogger.i('[Metronome] Engine pregătit');
    } catch (e) {
      AppLogger.e('[Metronome] Eroare la init audio', error: e);
    }
  }

  void start() {
    if (_running) return;
    _running = true;
    _beat = 0;
    _nextBeat = DateTime.now();
    AppLogger.i('[Metronome] Start — $bpm BPM, $beatsPerBar/4');
    _fireBeat();
    _armNext();
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    AppLogger.i('[Metronome] Stop');
  }

  void _armNext() {
    if (!_running) return;
    // Recalcul interval la fiecare bătaie → schimbarea de tempo e netedă.
    _nextBeat = _nextBeat.add(Duration(microseconds: (60000000 / bpm).round()));
    var delay = _nextBeat.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    _timer = Timer(delay, () {
      if (!_running) return;
      _beat++;
      _fireBeat();
      _armNext();
    });
  }

  void _fireBeat() {
    final beatInBar = _beat % beatsPerBar;
    final accent = beatInBar == 0;
    if (_ready) {
      final player = accent ? _accentPlayer : _normalPlayer;
      final wav = accent ? _accentWav : _normalWav;
      // Fire-and-forget — nu blochez programarea bătăii.
      unawaited(
        player.play(BytesSource(wav)).catchError((Object e) {
          AppLogger.w('[Metronome] play eșuat: $e');
        }),
      );
    }
    onBeat?.call(beatInBar, accent);
  }

  Future<void> dispose() async {
    stop();
    await _accentPlayer.dispose();
    await _normalPlayer.dispose();
  }

  /// Generează un click WAV PCM16 mono cu anvelopă atac-decay.
  ///
  /// Atacul scurt (4ms) elimină pop-ul transient (sinus pornit instant de
  /// la 0 → clic agresiv pe difuzor). Decăderea exponențială mai blândă
  /// (~24 vs 58 anterior) dă o senzație de „bip" curat, nu „pocnit".
  static Uint8List _clickWav({
    required double freq,
    required int durationMs,
    required double volume,
  }) {
    const sampleRate = 44100;
    const attackMs = 4;
    final n = sampleRate * durationMs ~/ 1000;
    final attackSamples = sampleRate * attackMs ~/ 1000;
    final samples = Int16List(n);
    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      // Atac de 4ms ramp + decay rapid (factor 58 ca în varianta inițială
      // — „tic", nu „beep" lung). Atacul elimină pop-ul transient.
      final attack = i < attackSamples ? i / attackSamples : 1.0;
      final decay = exp(-t * 58);
      final env = attack * decay;
      final s = sin(2 * pi * freq * t) * env * volume;
      samples[i] = (s * 32767).round().clamp(-32768, 32767);
    }
    final pcm = samples.buffer.asUint8List();
    final dataSize = pcm.length;

    final out = BytesBuilder();
    void str(String s) => out.add(s.codeUnits);
    void u32(int v) => out.add([
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ]);
    void u16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);

    str('RIFF');
    u32(36 + dataSize);
    str('WAVE');
    str('fmt ');
    u32(16); // Subchunk1Size
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2); // byte rate (mono, 16-bit)
    u16(2); // block align
    u16(16); // bits/sample
    str('data');
    u32(dataSize);
    out.add(pcm);
    return out.toBytes();
  }
}
