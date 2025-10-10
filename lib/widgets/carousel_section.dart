import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
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

  final String apiKey = 'YOUR_TMDB_API_KEY'; // replace with your key

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    try {
      final url = Uri.parse('https://api.themoviedb.org/3/${widget.endpoint}?api_key=$apiKey&language=en-US&page=1');
      final res = await http.get(url);
      final data = jsonDecode(res.body);
      setState(() {
        _items = (data['results'] ?? []).where((e) => e['poster_path'] != null).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFDAA520)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title,
            style: const TextStyle(
              color: Color(0xFFEAEAEA),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            )),
        const SizedBox(height: 12),
        CarouselSlider(
          options: CarouselOptions(
            height: 220,
            enableInfiniteScroll: true,
            viewportFraction: 0.45,
            enlargeCenterPage: false,
          ),
          items: _items.map((item) => MovieCard(item: item)).toList(),
        ),
      ],
    );
  }
}
