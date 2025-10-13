import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../widgets/movie_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool loading = true;
  String? error;
  User? user;
  List<dynamic> movies = [];
  List<dynamic> episodes = [];
  Map<String, bool> expandedShows = {};
  String activeTab = 'movies';

  @override
  void initState() {
    super.initState();
    _listenToAuth();
  }

  void _listenToAuth() {
    _auth.authStateChanges().listen((u) {
      setState(() => user = u);
      if (u != null) {
        _fetchHistory(u.uid);
      } else {
        setState(() {
          loading = false;
          movies = [];
          episodes = [];
        });
      }
    });
  }

  Future<void> _fetchHistory(String userId) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final docSnap = await _db.collection('history').doc(userId).get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        setState(() {
          movies = (data['movies'] ?? [])
            ..sort((a, b) => DateTime.parse(b['watchedAt'])
                .compareTo(DateTime.parse(a['watchedAt'])));
          episodes = (data['episodes'] ?? [])
            ..sort((a, b) => DateTime.parse(b['watchedAt'])
                .compareTo(DateTime.parse(a['watchedAt'])));
        });
      } else {
        setState(() {
          movies = [];
          episodes = [];
        });
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _clearHistory() async {
    if (user == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text("Clear History",
            style: TextStyle(color: Color(0xFFEAEAEA))),
        content: const Text(
          "Clear entire watch history? This cannot be undone.",
          style: TextStyle(color: Color(0xFFA0A0A0)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel",
                  style: TextStyle(color: Color(0xFFDAA520)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
              const Text("Clear", style: TextStyle(color: Colors.redAccent)))
        ],
      ),
    );
    if (confirm != true) return;
    await _db
        .collection('history')
        .doc(user!.uid)
        .set({'movies': [], 'episodes': []});
    setState(() {
      movies = [];
      episodes = [];
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("History cleared"),
      backgroundColor: Color(0xFFDAA520),
    ));
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final date = DateTime.parse(iso);
      return DateFormat.yMMMd().add_jm().format(date);
    } catch (_) {
      return '';
    }
  }

  Map<String, Map<String, dynamic>> get groupedEpisodes {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (var ep in episodes) {
      if (ep['tvShowId'] == null) continue;
      final id = ep['tvShowId'].toString();
      grouped[id] ??= {
        'title': ep['tvShowName'] ?? 'Untitled Show',
        'poster_path': ep['poster_path'],
        'episodes': []
      };
      grouped[id]!['episodes'].add(ep);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.poppinsTextTheme(
      Theme.of(context).textTheme,
    ).apply(
      bodyColor: const Color(0xFFEAEAEA),
      displayColor: const Color(0xFFEAEAEA),
    );

    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFDAA520)),
        ),
      );
    }

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Log In Required",
                  style: TextStyle(
                      color: Color(0xFFDAA520),
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                "Please log in to view your watch history.",
                style: TextStyle(color: Color(0xFFA0A0A0)),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFDAA520),
                    foregroundColor: Color(0xFF121212)),
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: const Text("Log In"),
              )
            ],
          ),
        ),
      );
    }

    if (error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Text(
            "Error loading history:\n$error",
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Watch History",
                    style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFEAEAEA))),
                if (movies.isNotEmpty || episodes.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearHistory,
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 18),
                    label: const Text("Clear History",
                        style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Tabs
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _tabButton('Movies', 'movies', Icons.movie),
                const SizedBox(width: 8),
                _tabButton('TV Episodes', 'episodes', Icons.tv),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: activeTab == 'movies'
                  ? _buildMoviesSection(textTheme)
                  : _buildEpisodesSection(textTheme),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tabButton(String label, String value, IconData icon) {
    final active = activeTab == value;
    return ElevatedButton.icon(
      icon: Icon(icon,
          color: active ? const Color(0xFF121212) : const Color(0xFFA0A0A0),
          size: 16),
      label: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF121212) : const Color(0xFFA0A0A0),
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor:
        active ? const Color(0xFFDAA520) : const Color(0xFF282828),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => setState(() => activeTab = value),
    );
  }

  Widget _buildMoviesSection(TextTheme textTheme) {
    if (movies.isEmpty) {
      return const Center(
        child: Text(
          "You haven't watched any movies yet.",
          style: TextStyle(color: Color(0xFFA0A0A0)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final movie = movies[index];
        return Column(
          children: [
            Expanded(child: MovieCard(movie: movie)),
            const SizedBox(height: 6),
            Text(
              _formatDate(movie['watchedAt']),
              style:
              const TextStyle(fontSize: 11, color: Color(0xFFA0A0A0)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEpisodesSection(TextTheme textTheme) {
    final grouped = groupedEpisodes;
    if (grouped.isEmpty) {
      return const Center(
        child: Text(
          "You haven't watched any TV episodes yet.",
          style: TextStyle(color: Color(0xFFA0A0A0)),
        ),
      );
    }

    return ListView(
      children: grouped.entries.map((entry) {
        final showId = entry.key;
        final show = entry.value;
        final eps = show['episodes'] as List;
        final expanded = expandedShows[showId] ?? false;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF282828),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: ExpansionTile(
            onExpansionChanged: (v) =>
                setState(() => expandedShows[showId] = v),
            initiallyExpanded: expanded,
            collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            title: Row(children: [
              show['poster_path'] != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  "https://image.tmdb.org/t/p/w500${show['poster_path']}",
                  width: 40,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              )
                  : const Icon(Icons.tv, color: Color(0xFFA0A0A0)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                    show['title'],
                    style: const TextStyle(
                        color: Color(0xFFEAEAEA), fontWeight: FontWeight.w600),
                  )),
              Text(
                "${eps.length} Ep.",
                style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
              ),
            ]),
            children: eps
                .map<Widget>((ep) => ListTile(
              dense: true,
              title: Text(
                "S${ep['seasonNumber']} E${ep['episodeNumber']}",
                style: const TextStyle(color: Color(0xFFEAEAEA)),
              ),
              subtitle: Text(
                _formatDate(ep['watchedAt']),
                style:
                const TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
              ),
            ))
                .toList(),
          ),
        );
      }).toList(),
    );
  }
}
