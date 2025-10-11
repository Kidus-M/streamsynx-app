import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TMDBService {
  static final String _baseUrl = 'https://api.themoviedb.org/3';
  static final String _apiKey = dotenv.env['TMDB_API_KEY'] ?? '';

  static Future<List<dynamic>> fetchContent(String endpoint, {Map<String, String>? params}) async {
    final uri = Uri.https('api.themoviedb.org', '/3/$endpoint', {
      'api_key': _apiKey,
      'language': 'en-US',
      ...?params,
    });

    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['results'];
    } else {
      throw Exception('Failed to load TMDB data: ${response.statusCode}');
    }
  }
}
