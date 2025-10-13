import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/movie_card.dart';

class RecommendedScreen extends StatefulWidget {
  const RecommendedScreen({super.key});

  @override
  State<RecommendedScreen> createState() => _RecommendedScreenState();
}

class _RecommendedScreenState extends State<RecommendedScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool loading = true;
  String? error;
  User? user;
  Map<String, dynamic> recommendations = {'movies': [], 'episodes': []};
  Map<String, String> usernames = {};
  String activeTab = 'movies';
  Map<String, bool> expandedShows = {};

  @override
  void initState() {
    super.initState();
    _listenToAuth();
  }

  void _listenToAuth() {
    _auth.authStateChanges().listen((u) {
      setState(() => user = u);
      if (u != null) {
        _fetchRecommendations(u.uid);
      } else {
        setState(() {
          loading = false;
          recommendations = {'movies': [], 'episodes': []};
        });
      }
    });
  }

  Future<void> _fetchRecommendations(String userId) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final docSnap = await _db.collection('recommendations').doc(userId).get();
      Map<String, dynamic> recData = {};
      if (docSnap.exists) {
        recData = docSnap.data() ?? {};
      }

      recData['movies'] = recData['movies'] ?? [];
      recData['episodes'] = recData['episodes'] ?? [];

      // Fetch usernames of recommenders
      final Set<String> uids = {};
      for (var item in [...recData['movies'], ...recData['episodes']]) {
        if (item['recommendedBy'] != null) uids.add(item['recommendedBy']);
      }

      final Map<String, String> fetchedNames = {};
      for (final id in uids) {
        try {
          final userDoc = await _db.collection('users').doc(id).get();
          if (userDoc.exists) {
            fetchedNames[id] = userDoc.data()?['username'] ?? 'Unknown User';
          } else {
            fetchedNames[id] = 'Unknown User';
          }
        } catch (_) {
          fetchedNames[id] = 'Error Loading Name';
        }
      }

      setState(() {
        recommendations = recData;
        usernames = fetchedNames;
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  Map<String, Map<String, dynamic>> get groupedEpisodes {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (var ep in (recommendations['episodes'] ?? [])) {
      if (ep['tvShowId'] == null) continue;
      final id = ep['tvShowId'].toString();
      grouped[id] ??= {
        'title': ep['tvShowName'] ?? 'Untitled Show',
        'poster_path': ep['poster_path'],
        'episodes': [],
        'recommendedBy': ep['recommendedBy']
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
              Text('Log In Required',
                  style: TextStyle(
                      color: Color(0xFFDAA520),
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                'Please log in to view your recommendations.',
                style: TextStyle(color: Color(0xFFA0A0A0)),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFDAA520),
                    foregroundColor: Color(0xFF121212)),
                onPressed: () => Navigator.pushNamed(context, '/login'),
                child: const Text('Log In'),
              ),
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
            'Error loading recommendations:\n$error',
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final movies = recommendations['movies'] ?? [];
    final episodes = recommendations['episodes'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Recommended For You",
                    style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFEAEAEA))),
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

                // Tab Content
                Expanded(
                  child: activeTab == 'movies'
                      ? _buildMoviesSection(movies, textTheme)
                      : _buildEpisodesSection(episodes, textTheme),
                )
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

  Widget _buildMoviesSection(List movies, TextTheme textTheme) {
    if (movies.isEmpty) {
      return const Center(
        child: Text("No recommended movies found.",
            style: TextStyle(color: Color(0xFFA0A0A0))),
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
        final recommender =
            usernames[movie['recommendedBy']] ?? 'Unknown User';
        return Column(
          children: [
            Expanded(child: MovieCard(movie: movie)),
            const SizedBox(height: 6),
            Text(
              "Rec by: $recommender",
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFFA0A0A0)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }

  Widget _buildEpisodesSection(List episodes, TextTheme textTheme) {
    final grouped = groupedEpisodes;
    if (grouped.isEmpty) {
      return const Center(
        child: Text("No recommended TV episodes found.",
            style: TextStyle(color: Color(0xFFA0A0A0))),
      );
    }

    return ListView(
      children: grouped.entries.map((entry) {
        final showId = entry.key;
        final show = entry.value;
        final eps = show['episodes'] as List;
        final expanded = expandedShows[showId] ?? false;
        final recommender =
            usernames[show['recommendedBy']] ?? 'Unknown User';
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        show['title'],
                        style: const TextStyle(
                            color: Color(0xFFEAEAEA),
                            fontWeight: FontWeight.w600),
                      ),
                      Text(
                        "Rec by: $recommender",
                        style: const TextStyle(
                            color: Color(0xFFA0A0A0), fontSize: 12),
                      ),
                    ],
                  )),
              Text(
                "${eps.length} Rec",
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
            ))
                .toList(),
          ),
        );
      }).toList(),
    );
  }
}
