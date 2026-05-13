import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/health_response.dart';
import '../utils/app_logger.dart';
import '../utils/constants.dart';

class ApiService {
  Future<HealthResponse> checkHealth() async {
    final url = '${ApiConstants.apiBaseUrl}${ApiConstants.endpointHealth}';
    final uri = Uri.parse(url);

    AppLogger.i('🌐 [ApiService] GET $url');

    try {
      final response = await http.get(uri).timeout(ApiConstants.apiTimeout);

      AppLogger.i('✅ [ApiService] Răspuns: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('Eroare server: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return HealthResponse.fromJson(json);
    } on TimeoutException catch (e) {
      AppLogger.e(
        '❌ [ApiService] Timeout la conexiunea cu backend-ul',
        error: e,
      );
      throw Exception(
        'Backend-ul nu răspunde (timeout ${ApiConstants.apiTimeout.inSeconds}s)',
      );
    } on SocketException catch (e) {
      AppLogger.e('❌ [ApiService] Nu pot conecta la backend', error: e);
      throw Exception(
        'Nu pot conecta la backend. Verifică că serverul rulează.',
      );
    } on FormatException catch (e) {
      AppLogger.e('❌ [ApiService] Răspuns invalid de la backend', error: e);
      throw Exception('Răspuns invalid de la backend');
    } catch (e) {
      AppLogger.e('❌ [ApiService] Eroare neașteptată', error: e);
      rethrow;
    }
  }
}
