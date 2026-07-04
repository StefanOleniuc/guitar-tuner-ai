import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../utils/app_logger.dart';
import 'pitch_service.dart';

/// Sintetizează și redă **note de referință** pentru fiecare coardă.
///
/// Folosim algoritmul **Karplus-Strong** (delay-line cu feedback și
/// lowpass), care modelează fizic o coardă plucată. Sună aproape de un
/// sample real de chitară, cu zero MB-uri de assets — o coardă, nu o
/// sinusoidă. Plus:
///   * **pluck noise** (excitație inițială filtrată ușor → mai puțin „fizz");
///   * **lowpass de feedback** controlat per notă (notele înalte fade mai
///     repede, ca în realitate);
///   * **soft body-resonance**: un mic ecou întârziat (adaugă „corpul"
///     chitarei — fără el sună prea „nud").
///
/// Tot codul rulează la 44.1kHz mono, în memorie, cache-uit per
/// combinație (notă × A4).
///
/// WAV-urile sunt cache-uite pe combinația notă+A4: o notă cântată de
/// două ori NU regenerează datele audio.
class NoteAudio {
  NoteAudio._();
  static final NoteAudio instance = NoteAudio._();

  // Pool de 3 playere — round-robin. Pe Android, `audioplayers` se poate
  // bloca într-o tranziție stop↔play dacă userul dă tap-uri în rafală pe
  // același player (rămâne într-un state "stopping" și nu mai răspunde).
  // Cu un pool, fiecare tap merge pe alt player → chiar dacă unul se
  // blochează temporar, următoarele tap-uri se aud imediat.
  final List<AudioPlayer> _pool = [AudioPlayer(), AudioPlayer(), AudioPlayer()];
  int _poolIdx = 0;
  final Map<String, Uint8List> _cache = {};

  /// Generează (dacă e nevoie) și redă nota dată. Întrerupe sunetul anterior
  /// — userul nu vrea două note suprapuse când dă tap rapid.
  Future<void> play(String fullNote, {double a4 = 440.0}) async {
    try {
      final freq = PitchService.noteToFrequency(fullNote, a4: a4);
      final key = '${fullNote}_${a4.toStringAsFixed(1)}';
      final wav = _cache.putIfAbsent(key, () => _noteWav(freq));

      // Stop pe playerul curent (cel care încă mai sună), fire-and-forget
      // — NU așteptăm; await-ul pe stop a fost cauza blocajelor.
      final prev = _pool[_poolIdx];
      unawaited(prev.stop().catchError((_) {}));

      // Pick următorul player din pool și redă pe el. Round-robin lasă
      // playerului anterior ~2 tap-uri ca să se recupereze din stop().
      _poolIdx = (_poolIdx + 1) % _pool.length;
      final next = _pool[_poolIdx];
      await next.play(BytesSource(wav));
    } catch (e) {
      AppLogger.w('[NoteAudio] Redare eșuată ($fullNote): $e');
    }
  }

  /// Eliberează resursele. De apelat la închiderea aplicației — momentan
  /// nu o facem explicit (singleton-ul trăiește cât app-ul).
  Future<void> dispose() async {
    _cache.clear();
    for (final p in _pool) {
      await p.dispose();
    }
  }

  /// Sintetizează ~1.6s de notă printr-un **Karplus-Strong extins**:
  ///
  /// 1. **Excitația**: ~6ms de zgomot lowpassed (medie mobilă pe 3 sample-uri)
  ///    încarcă delay-line-ul. Suficient de „brut" ca să excite toate
  ///    armonicele, suficient de filtrat ca să nu sune ca un click metalic.
  /// 2. **Delay-line**: lungime = `sampleRate / freq` sample-uri. La
  ///    fiecare pas: sample-ul iese din delay, e amestecat cu următorul
  ///    (`y[i] = (x[i] + x[i+1]) * 0.5 * decay`) și se reintroduce la
  ///    capăt. Acest filtru de mediere = lowpass care „închide" timbrul
  ///    treptat, exact ca o coardă reală.
  /// 3. **Decay**: factor sub-unitar pe feedback. Cu cât freq e mai mare,
  ///    cu atât bucla e mai scurtă, cu atât decay-ul efectiv per secundă
  ///    e mai agresiv → notele înalte fade mai repede. Ajustăm
  ///    `decay` în funcție de freq ca să compensăm parțial.
  /// 4. **Body resonance**: un al doilea delay-line foarte scurt cu
  ///    feedback mic adaugă „corpul" rezonant al chitarei.
  static Uint8List _noteWav(double freq) {
    const sampleRate = 44100;
    const durationMs = 1600;
    final n = sampleRate * durationMs ~/ 1000;

    // Lungimea buclei de delay (în sample-uri). Folosim Float pentru
    // micro-tuning prin interpolare liniară între două sample-uri vecine
    // → frecvența rezultată e exact `freq`, fără cuantizarea cauzată de
    // un întreg apropiat.
    final delayLenF = sampleRate / freq;
    final delayLen = delayLenF.floor();
    final frac = delayLenF - delayLen; // 0..1
    final buf = Float32List(delayLen + 1); // +1 pentru interpolare la coadă

    // Excitația: ~6ms de zgomot alb filtrat (medie pe 3 sample-uri).
    // Seed fix → output deterministic, cache-friendly.
    final rng = Random(42);
    final excLen = (sampleRate * 0.006).round().clamp(8, delayLen);
    final raw = Float32List(excLen + 2);
    for (int i = 0; i < raw.length; i++) {
      raw[i] = rng.nextDouble() * 2 - 1;
    }
    for (int i = 0; i < excLen; i++) {
      buf[i] = (raw[i] + raw[i + 1] + raw[i + 2]) * (1.0 / 3.0);
    }
    // Restul buf-ului rămâne zero — coarda e „liniștită" înainte de
    // a se propaga excitația prin buclă.

    // Decay-ul feedback-ului. Pentru note înalte (delayLen mic) trebuie
    // mai aproape de 1, altfel se sting prea repede.
    // Empiric: decay ≈ 0.994 pentru E2, ≈ 0.998 pentru E5.
    final decay = (0.992 + (1.0 - (delayLen / 600).clamp(0.0, 1.0)) * 0.006)
        .clamp(0.985, 0.999);

    // Body-resonance: un delay scurt (~3ms) cu feedback mic — adaugă
    // o ușoară rezonanță difuză tip „cutie de chitară".
    final bodyLen = (sampleRate * 0.0028).round();
    final body = Float32List(bodyLen);
    int bodyIdx = 0;
    const bodyMix = 0.18;
    const bodyFeedback = 0.35;

    final out = Int16List(n);
    int p = 0; // pointer curent în delay-line
    // Anvelopă globală foarte blândă — strict ca să nu „taie" la final.
    final tailStart = (n * 0.86).round();
    for (int i = 0; i < n; i++) {
      // Citește cu interpolare liniară între buf[p] și buf[p+1].
      final s0 = buf[p];
      final s1 = buf[(p + 1) % buf.length];
      final sample = s0 * (1.0 - frac) + s1 * frac;

      // Body resonance: ușor delay + feedback mic.
      final bodySample = body[bodyIdx];
      body[bodyIdx] = sample + bodySample * bodyFeedback;
      bodyIdx = (bodyIdx + 1) % bodyLen;
      var mixed = sample + bodySample * bodyMix;

      // Anvelopă coadă (ultimii 14% fade liniar la 0) ca să eviți pop.
      if (i > tailStart) {
        final t = (i - tailStart) / (n - tailStart);
        mixed *= 1.0 - t;
      }

      // Clip soft (tanh-like) ca să prevenim depășiri rare la atac.
      if (mixed > 1.0) {
        mixed = 1.0;
      } else if (mixed < -1.0) {
        mixed = -1.0;
      }
      out[i] = (mixed * 0.85 * 32767).round();

      // Karplus-Strong update: înlocuiește buf[p] cu media cu vecinul,
      // scalată cu decay (filtrul lowpass în feedback).
      final nextP = (p + 1) % buf.length;
      buf[p] = (buf[p] + buf[nextP]) * 0.5 * decay;
      p = nextP;
    }
    return _pcmToWav(out, sampleRate);
  }

  static Uint8List _pcmToWav(Int16List samples, int sampleRate) {
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
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    str('data');
    u32(dataSize);
    out.add(pcm);
    return out.toBytes();
  }
}
