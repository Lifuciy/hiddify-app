import 'dart:convert';
import 'package:http/http.dart' as http;

class PxyApi {
  static const String baseUrl = 'https://api.marakastaraka.ru';

  static Future<Map<String, dynamic>> activate({
    required String code,
    required String deviceId,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/activate');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'device_id': deviceId}),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
