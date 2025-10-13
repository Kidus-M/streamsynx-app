import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/movie_card.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({Key? key}) : super(key: key);

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? user;
  bool loading = true;
  List<dynamic> watchlistItems = [];
  String filter = 'all'; // 'all', 'movie', 'tv'

  @override
  void initState() {
    super.initState();
    _listenToAuth();
  }

  void _listenToAuth() {
    _auth.authStateChanges().listen((User? currentUser) {
      setState(() {
        user = currentUser;
      });
      if (currentUser != null) {
        _fetchWatchlist(currentUser.uid);
      } else {
        setState(() {
          loading = false;
          watchlistItems = [];
        });
      }
    });
  }

  Future<void> _fetchWatchlist(String userId) async {
    setState(() => loading = true);
    try {
      final docSnap = await _db.collection('watchlists').doc(userId).get();
      if (docSnap.exists) {
        setState(() {
          watchlistItems = docSnap.data()?['items'] ?? [];
        });
      } else {
        setState(() {
          watchlistItems = [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching watchlist: $e');
      setState(() {
        watchlistItems = [];
      });
    } finally {
      setState(() => loading = false);
    }
  }

  List<dynamic> get filteredItems {
    if (filter == 'all') return watchlistItems;
    return watchlistItems
        .where((item) => item['media_type'] == filter)
        .toList();
  }

  Widget _buildFilterButton(String label, String value, IconData icon) {
    final bool active = filter == value;
    return ElevatedButton.icon(
      icon: Icon(
        icon,
        size: 16,
        color: active ? const Color(0xFF121212) : const Color(0xFFA0A0A0),
      ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      onPressed: () => setState(() => filter = value),
    );
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
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFDAA520)),
        ),
      );
    }

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Log In Required',
                  style: textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFDAA520),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Please log in to view your watchlist.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFA0A0A0),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, '/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDAA520),
                    foregroundColor: const Color(0xFF121212),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Log In'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                "My Watchlist",
                style: textTheme.titleLarge?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFEAEAEA),
                ),
              ),
              const SizedBox(height: 16),

              // Filter buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFilterButton('All', 'all', Icons.list),
                  const SizedBox(width: 8),
                  _buildFilterButton('Movies', 'movie', Icons.movie),
                  const SizedBox(width: 8),
                  _buildFilterButton('TV Shows', 'tv', Icons.tv),
                ],
              ),
              const SizedBox(height: 16),

              // Watchlist content
              Expanded(
                child: filteredItems.isNotEmpty
                    ? GridView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return MovieCard(movie: item);
                  },
                )
                    : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.list_alt,
                          size: 50, color: Color(0xFFA0A0A0)),
                      const SizedBox(height: 10),
                      Text(
                        "Your watchlist is empty.",
                        style: textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFFA0A0A0),
                        ),
                      ),
                      Text(
                        "Add movies and TV shows to see them here.",
                        style: textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFA0A0A0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
