import 'package:flutter/material.dart';
import 'package:carousel_slider_plus/carousel_slider_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart'; // ✅ for secure API key
import 'movie_card.dart';

class CarouselSection extends StatefulWidget {
  final String title;
  final String type;
  final String endpoint;

  const CarouselSection({
    super.key,
    required this.title,
    required this.type,
    required this.endpoint,
  });

  @override
  State<CarouselSection> createState() => _CarouselSectionState();
}

class _CarouselSectionState extends State<CarouselSection> {
  List<dynamic> _items = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    final apiKey = dotenv.env['TMDB_API_KEY']; // ✅ reads from .env
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('❌ TMDB API key missing in .env');
      setState(() {
        _error = true;
        _loading = false;
      });
      return;
    }

    try {
      final url = Uri.parse(
          'https://api.themoviedb.org/3/${widget.endpoint}?api_key=$apiKey&language=en-US&page=1${widget.endpoint.contains('discover') ? '&sort_by=vote_average.desc' : ''}');
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _items = (data['results'] ?? [])
              .where((e) => e['poster_path'] != null)
              .toList();
          _loading = false;
        });
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching TMDB data: $e');
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFDAA520)));
    }

    if (_error || _items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '⚠️ Failed to load ${widget.title}',
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            color: Color(0xFFEAEAEA),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        CarouselSlider(
          options: CarouselOptions(
            height: 220,
            enableInfiniteScroll: true,
            viewportFraction: 0.45,
            enlargeCenterPage: false,
            padEnds: false,
          ),
          items: _items.map((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: MovieCard(item: item),
            );
          }).toList(),
        ),
      ],
    );
  }
}
