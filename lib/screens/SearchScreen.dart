// File: lib/screens/search_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

  String? _type; // "movie" or "tv" or null
  String? _year;
  String? _genre;

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }

    final apiKey = dotenv.env['TMDB_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('❌ TMDB API key missing in .env');
      return;
    }

    setState(() => _loading = true);

    try {
      final url = Uri.parse(
          'https://api.themoviedb.org/3/search/multi?api_key=$apiKey&language=en-US&include_adult=false&query=$query&page=1');
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = (data['results'] ?? [])
            .where((e) => e['poster_path'] != null && (e['media_type'] == 'movie' || e['media_type'] == 'tv'))
            .toList();

        // Client-side filtering
        final yearInt = (_year != null && _year!.length == 4) ? int.tryParse(_year!) : null;
        final genreInt = _genre != null ? int.tryParse(_genre!) : null;

        final filtered = results.where((item) {
          final mediaType = item['media_type'];
          if (_type != null && mediaType != _type) return false;

          if (yearInt != null) {
            final itemYearStr = mediaType == 'movie'
                ? item['release_date']?.substring(0, 4)
                : item['first_air_date']?.substring(0, 4);
            final itemYearInt = itemYearStr != null ? int.tryParse(itemYearStr) : null;
            if (itemYearInt != yearInt) return false;
          }

          if (genreInt != null) {
            final genres = item['genre_ids'] as List<dynamic>?;
            if (genres == null || !genres.contains(genreInt)) return false;
          }

          return true;
        }).toList();

        setState(() => _results = filtered);
      } else {
        debugPrint('⚠️ Failed to fetch search: ${res.statusCode}');
        setState(() => _results = []);
      }
    } catch (e) {
      debugPrint('⚠️ Search error: $e');
      setState(() => _results = []);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Search', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search input
            TextField(
              controller: _controller,
              onChanged: _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search movies or shows...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF282828),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),

            // Filters row: Type and Year
            Row(
              children: [
                DropdownButton<String>(
                  value: _type,
                  hint: const Text('All', style: TextStyle(color: Colors.white)),
                  dropdownColor: const Color(0xFF282828),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 'movie', child: Text('Movies', style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(value: 'tv', child: Text('TV Shows', style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (value) {
                    setState(() => _type = value);
                    _search(_controller.text);
                  },
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Year',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF282828),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
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
            const SizedBox(height: 16),

            // Results
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFDAA520)))
                  : _results.isEmpty
                  ? const Center(child: Text('No results', style: TextStyle(color: Colors.grey)))
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.65,
                ),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  return MovieCard(movie: _results[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
