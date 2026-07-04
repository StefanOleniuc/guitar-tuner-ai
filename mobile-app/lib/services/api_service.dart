import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/crepe_pitch_result.dart';
import '../utils/app_logger.dart';
import '../utils/constants.dart';

class ApiService {
  /// Trimite un sample PCM16 (~0.8s) la backend pentru detecție AI CREPE.
  /// Returnează null la orice eroare — apelantul afișează un mesaj prietenos.
  Future<CrepePitchResult?> detectPitchAI(Uint8List pcm16Bytes) async {
    final url =
        '${ApiConstants.apiBaseUrl}${ApiConstants.endpointDetectPitchAI}';
    final uri = Uri.parse(url);

    AppLogger.i(
      '🌐 [ApiService] CREPE request: ${pcm16Bytes.length} bytes → $url',
    );

    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            pcm16Bytes,
            filename: 'audio.pcm',
          ),
        );

      // Cronometrăm round-trip-ul real al cererii CREPE (rețea + inferență pe
      // server), ca să putem raporta o latență măsurată, nu estimată.
      final sw = Stopwatch()..start();
      final streamed = await request.send().timeout(ApiConstants.aiTimeout);
      final response = await http.Response.fromStream(streamed);
      sw.stop();
      AppLogger.i(
        '⏱️ [ApiService] CREPE latență (round-trip): ${sw.elapsedMilliseconds} ms',
      );

      if (response.statusCode != 200) {
        AppLogger.e(
          '❌ [ApiService] CREPE status ${response.statusCode}: ${response.body}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = CrepePitchResult.fromJson(json);

      AppLogger.i(
        '✅ [ApiService] CREPE response: ${result.frequency.toStringAsFixed(2)} Hz, '
        'conf ${(result.confidence * 100).toStringAsFixed(0)}%',
      );
      return result;
    } on TimeoutException catch (e) {
      AppLogger.e('❌ [ApiService] CREPE timeout', error: e);
      return null;
    } on SocketException catch (e) {
      AppLogger.e('❌ [ApiService] CREPE: nu pot conecta la backend', error: e);
      return null;
    } on FormatException catch (e) {
      AppLogger.e('❌ [ApiService] CREPE: răspuns JSON invalid', error: e);
      return null;
    } catch (e, st) {
      AppLogger.e(
        '❌ [ApiService] CREPE: eroare neașteptată',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
