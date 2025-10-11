import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/stats_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _loading = true;
  bool _editing = false;
  String? _username;
  String? _email;
  String? _avatar;
  String? _error;

  int buddies = 0;
  int moviesWatched = 0;
  int episodesWatched = 0;
  int favMovies = 0;
  int favEpisodes = 0;
  int favShows = 0;
  String topGenre = "N/A";

  final Map<int, String> genreMap = {
    28: "Action",
    12: "Adventure",
    16: "Animation",
    35: "Comedy",
    80: "Crime",
    18: "Drama",
    14: "Fantasy",
    10751: "Family",
    878: "Sci-Fi",
    27: "Horror",
    10759: "Action & Adventure",
    // add more if needed
  };

  @override
  void initState() {
    super.initState();
    _fetchUserDataAndStats();
  }

  Future<void> _fetchUserDataAndStats() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _error = "Please log in to view your profile.";
        _loading = false;
      });
      return;
    }

    try {
      // 1. Fetch user doc
      final userDocSnap = await _db.collection('users').doc(user.uid).get();
      if (userDocSnap.exists) {
        final data = userDocSnap.data()!;
        _username = data['username'] as String?;
        _email = data['email'] as String?;
        _avatar = data['avatar'] as String?;
      }

      // 2. Fetch friends document (to get "buddies")
      final friendsSnap = await _db.collection('friends').doc(user.uid).get();
      if (friendsSnap.exists) {
        final friendsData = friendsSnap.data()!;
        final List<dynamic>? friendsList = friendsData['friends'] as List<dynamic>?;
        buddies = friendsList?.length ?? 0;
      } else {
        buddies = 0;
      }

      // 3. Fetch history doc
      final historySnap = await _db.collection('history').doc(user.uid).get();
      Map<String, dynamic> history = {};
      if (historySnap.exists) {
        history = historySnap.data()!;
      }

      // 4. Fetch favorites doc
      final favSnap = await _db.collection('favorites').doc(user.uid).get();
      Map<String, dynamic> favorites = {};
      if (favSnap.exists) {
        favorites = favSnap.data()!;
      }

      // 5. Compute counts
      moviesWatched = (history['movies'] as List<dynamic>?)?.length ?? 0;
      episodesWatched = (history['episodes'] as List<dynamic>?)?.length ?? 0;
      favMovies = (favorites['movies'] as List<dynamic>?)?.length ?? 0;
      favEpisodes = (favorites['episodes'] as List<dynamic>?)?.length ?? 0;
      favShows = (favorites['shows'] as List<dynamic>?)?.length ?? 0;

      // 6. Compute top genre
      Map<int, int> genreCounts = {};
      final List<dynamic>? movieList = history['movies'] as List<dynamic>?;
      final List<dynamic>? episodeList = history['episodes'] as List<dynamic>?;
      final allHistory = <dynamic>[];
      if (movieList != null) allHistory.addAll(movieList);
      if (episodeList != null) allHistory.addAll(episodeList);

      for (var item in allHistory) {
        if (item is Map<String, dynamic>) {
          // Prefer genre_ids if present
          if (item['genre_ids'] is List<dynamic>) {
            for (var g in (item['genre_ids'] as List<dynamic>)) {
              if (g is int) {
                genreCounts[g] = (genreCounts[g] ?? 0) + 1;
              }
            }
          } else if (item['genres'] is List<dynamic>) {
            for (var g in (item['genres'] as List<dynamic>)) {
              if (g is Map<String, dynamic> && g['id'] is int) {
                int gid = g['id'];
                genreCounts[gid] = (genreCounts[gid] ?? 0) + 1;
              }
            }
          }
        }
      }

      if (genreCounts.isNotEmpty) {
        final topEntry = genreCounts.entries.reduce((a, b) => a.value > b.value ? a : b);
        topGenre = genreMap[topEntry.key] ?? "Unknown (${topEntry.key})";
      }

    } catch (e) {
      print("Error in fetching profile stats: $e");
      _error = e.toString();
    }

    // Update UI
    setState(() {
      _loading = false;
    });
  }

  Future<void> _saveUsername() async {
    final user = _auth.currentUser;
    if (user == null || _username == null || _username!.trim().isEmpty) return;

    try {
      await _db.collection('users').doc(user.uid).update({
        'username': _username!.trim(),
        'username_lowercase': _username!.trim().toLowerCase(),
      });
      setState(() {
        _editing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Username updated successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update username: $e")),
      );
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFDAA520)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Text(_error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: _avatar != null
                    ? NetworkImage(_avatar!)
                    : NetworkImage(
                    'https://www.gravatar.com/avatar/${_auth.currentUser?.uid}?d=mp&f=y'),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _editing
                    ? Column(
                  children: [
                    TextField(
                      onChanged: (v) => _username = v,
                      controller:
                      TextEditingController(text: _username ?? ''),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF282828),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFDAA520), width: 1.2),
                        ),
                        hintText: "Enter new username",
                        hintStyle: const TextStyle(color: Colors.grey),
                      ),
                      style: const TextStyle(
                          color: Color(0xFFEAEAEA), fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _saveUsername,
                      icon: const Icon(Icons.save, color: Colors.black),
                      label: const Text("Save",
                          style: TextStyle(color: Colors.black)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDAA520),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _editing = false),
                      child: const Text("Cancel",
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                )
                    : Column(
                  children: [
                    Text(
                      _username ?? "Username not set",
                      style: const TextStyle(
                          fontSize: 20,
                          color: Color(0xFFEAEAEA),
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(_email ?? "",
                        style:
                        const TextStyle(color: Color(0xFFA0A0A0))),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon:
                      const Icon(Icons.edit, color: Color(0xFFDAA520)),
                      label: const Text("Edit Username",
                          style: TextStyle(color: Color(0xFFDAA520))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFFDAA520), width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const Divider(color: Color(0xFF333333)),
              const SizedBox(height: 10),
              const Text(
                "Your Stats",
                style: TextStyle(
                    color: Color(0xFFEAEAEA),
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  StatsCard(title: "Buddies", value: "$buddies"),
                  StatsCard(title: "Movies Watched", value: "$moviesWatched"),
                  StatsCard(title: "Episodes Watched", value: "$episodesWatched"),
                  StatsCard(title: "Favorite Movies", value: "$favMovies"),
                  // StatsCard(title: "Favorite Shows", value: "$favShows"),
                  StatsCard(title: "Favorite Episodes", value: "$favEpisodes"),
                  StatsCard(title: "Top Genre", value: topGenre),
                ],
              ),
              const SizedBox(height: 30),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                label: const Text("Logout",
                    style: TextStyle(color: Colors.redAccent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
