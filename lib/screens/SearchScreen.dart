// File: lib/screens/search_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:carousel_slider_plus/carousel_slider_plus.dart';
import '../widgets/movie_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;

  String? _type;
  String? _year;

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    final apiKey = dotenv.env['TMDB_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('❌ Missing TMDB API key');
      return;
    }

    setState(() => _loading = true);

    try {
      final url = Uri.parse(
        'https://api.themoviedb.org/3/search/multi?api_key=$apiKey&language=en-US&include_adult=false&query=$query',
      );
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        List results = (data['results'] ?? [])
            .where((e) =>
        e['poster_path'] != null &&
            (e['media_type'] == 'movie' || e['media_type'] == 'tv'))
            .toList();

        // Filter by type/year
        final yearInt = (_year != null && _year!.length == 4)
            ? int.tryParse(_year!)
            : null;
        results = results.where((item) {
          final mediaType = item['media_type'];
          if (_type != null && mediaType != _type) return false;

          if (yearInt != null) {
            final itemYear = mediaType == 'movie'
                ? item['release_date']?.substring(0, 4)
                : item['first_air_date']?.substring(0, 4);
            return itemYear == _year;
          }
          return true;
        }).toList();

        setState(() => _results = results);
      } else {
        debugPrint('❌ HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching search results: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFFDAA520)),
            ),
            const Text(
              'Search',
              style: TextStyle(
                color: Color(0xFFEAEAEA),
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 🔍 Glassy Search Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: TextField(
              controller: _controller,
              onChanged: _search,
              style: const TextStyle(color: Colors.white),
              cursorColor: const Color(0xFFDAA520),
              decoration: InputDecoration(
                hintText: 'Search for movies or TV shows...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon:
                const Icon(Icons.search, color: Color(0xFFDAA520)),
                border: InputBorder.none,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          // 🎚 Filters (modernized look)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _type,
                    dropdownColor: const Color(0xFF1E1E1E),
                    iconEnabledColor: const Color(0xFFDAA520),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                        const BorderSide(color: Color(0xFF333333)),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    hint: const Text('All Types',
                        style: TextStyle(color: Colors.grey)),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('All'),
                      ),
                      DropdownMenuItem(
                        value: 'movie',
                        child: Text('Movies'),
                      ),
                      DropdownMenuItem(
                        value: 'tv',
                        child: Text('TV Shows'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _type = value);
                      _search(_controller.text);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Year',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                        const BorderSide(color: Color(0xFF333333)),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (val) {
                      setState(() => _year = val);
                      _search(_controller.text);
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 🎞 Results section
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _loading
                  ? Center(
                key: const ValueKey('loading'),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(
                        color: Color(0xFFDAA520)),
                    SizedBox(height: 12),
                    Text(
                      'Finding results...',
                      style: TextStyle(
                          color: Color(0xFFA0A0A0), fontSize: 16),
                    ),
                  ],
                ),
              )
                  : _results.isEmpty
                  ? Center(
                key: const ValueKey('empty'),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.search_off,
                        color: Color(0xFF555555), size: 60),
                    SizedBox(height: 8),
                    Text(
                      'No results found',
                      style: TextStyle(
                          color: Color(0xFFA0A0A0), fontSize: 16),
                    ),
                  ],
                ),
              )
                  : GridView.builder(
                key: const ValueKey('results'),
                padding: const EdgeInsets.all(16),
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.65,
                ),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  return AnimatedScale(
                    scale: 1,
                    duration: const Duration(milliseconds: 300),
                    child: MovieCard(movie: _results[index]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
