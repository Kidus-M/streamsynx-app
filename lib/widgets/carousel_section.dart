import 'package:flutter/material.dart';
import 'package:carousel_slider_plus/carousel_slider_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
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
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    final apiKey = dotenv.env['TMDB_API_KEY'];
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
        'https://api.themoviedb.org/3/${widget.endpoint}'
            '${widget.endpoint.contains('?') ? '&' : '?'}api_key=$apiKey&language=en-US&page=1',
      );

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
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFDAA520)),
        ),
      );
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
        Padding(
          padding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            widget.title,
            style: GoogleFonts.poppins(
              color: const Color(0xFFEAEAEA),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CarouselSlider.builder(
          itemCount: _items.length,
          itemBuilder: (context, index, realIdx) {
            final item = _items[index];
            final bool isActive = index == _currentIndex;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              transform: Matrix4.identity()
                ..scale(isActive ? 1.08 : 0.9), // ✅ Grows center card
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 24),
              child: Opacity(
                opacity: isActive ? 1.0 : 0.6,
                child: MovieCard(movie: item),
              ),
            );
          },
          options: CarouselOptions(
            height: 320, // ✅ Taller — no clipping
            enlargeCenterPage: true,
            viewportFraction: 0.55,
            padEnds: true,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 5),
            enableInfiniteScroll: true,
            onPageChanged: (index, reason) {
              setState(() => _currentIndex = index);
            },
          ),
        ),
      ],
    );
  }
}
