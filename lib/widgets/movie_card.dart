import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color primary = Color(0xFF121212);
const Color secondary = Color(0xFF282828);
const Color accent = Color(0xFFDAA520);
const Color textPrimary = Color(0xFFEAEAEA);
const Color textSecondary = Color(0xFFA0A0A0);

class MovieCard extends StatelessWidget {
  final dynamic item;
  const MovieCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final String imageUrl = 'https://image.tmdb.org/t/p/w500${item['poster_path']}';
    final String title = item['title'] ?? item['name'] ?? 'Untitled';

    return GestureDetector(
      onTap: () => showMovieDetailsModal(context, item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Image.network(imageUrl, height: 220, fit: BoxFit.cover, width: double.infinity),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black54, Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
            Positioned(
              left: 8, bottom: 8, right: 8,
              child: Text(
                title,
                style: const TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showMovieDetailsModal(BuildContext context, dynamic movie) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: secondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => MovieDetailModal(movie: movie),
  );
}

class MovieDetailModal extends StatefulWidget {
  final dynamic movie;
  const MovieDetailModal({super.key, required this.movie});

  @override
  State<MovieDetailModal> createState() => _MovieDetailModalState();
}

class _MovieDetailModalState extends State<MovieDetailModal> {
  bool isFavorite = false;
  bool isInWatchlist = false;
  double rating = 0;
  String selectedFriend = "";

  final user = FirebaseAuth.instance.currentUser;
  final db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final String poster = 'https://image.tmdb.org/t/p/w500${movie['poster_path']}';
    final String title = movie['title'] ?? movie['name'] ?? 'Untitled';
    final String overview = movie['overview'] ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Image.network(poster, fit: BoxFit.cover, height: 250, width: double.infinity),
                ),
                Positioned(
                  top: 10, right: 10,
                  child: IconButton(
                    icon: Icon(isInWatchlist ? Icons.check_circle : Icons.add_circle_outline,
                        color: accent, size: 28),
                    onPressed: toggleWatchlist,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(overview, style: const TextStyle(color: textSecondary, fontSize: 14)),
                  const SizedBox(height: 16),

                  // --- FAVORITE ---
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: accent, size: 28),
                        onPressed: toggleFavorite,
                      ),
                      const SizedBox(width: 8),
                      const Text("Favorite", style: TextStyle(color: textPrimary)),
                    ],
                  ),

                  // --- RATING ---
                  const SizedBox(height: 12),
                  Text("Rate:", style: const TextStyle(color: textSecondary)),
                  Row(
                    children: List.generate(5, (i) {
                      final starValue = (i + 1) * 2;
                      return IconButton(
                        icon: Icon(
                          starValue <= rating ? Icons.star : Icons.star_border,
                          color: accent,
                        ),
                        onPressed: () => setRating(starValue.toDouble()),
                      );
                    }),
                  ),

                  // --- RECOMMENDATION ---
                  const SizedBox(height: 12),
                  Text("Recommend to:", style: const TextStyle(color: textSecondary)),
                  DropdownButton<String>(
                    value: selectedFriend.isEmpty ? null : selectedFriend,
                    hint: const Text("Select Friend", style: TextStyle(color: textSecondary)),
                    dropdownColor: secondary,
                    items: const [
                      DropdownMenuItem(value: "friend1", child: Text("Friend 1")),
                      DropdownMenuItem(value: "friend2", child: Text("Friend 2")),
                    ],
                    onChanged: (v) => setState(() => selectedFriend = v ?? ""),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: recommendMovie,
                    icon: const Icon(Icons.send, color: primary),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent, foregroundColor: primary),
                    label: const Text("Send Recommendation"),
                  ),

                  // --- SHARE POSTER ---
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Share.share("Check out $title! $poster"),
                    icon: const Icon(Icons.share, color: primary),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accent, foregroundColor: primary),
                    label: const Text("Share Poster"),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void toggleFavorite() async {
    setState(() => isFavorite = !isFavorite);
    // Firestore favorites logic here using arrayUnion/arrayRemove
  }

  void toggleWatchlist() async {
    setState(() => isInWatchlist = !isInWatchlist);
    // Firestore watchlist logic here
  }

  void setRating(double value) async {
    setState(() => rating = value);
    // Save to Firestore ratings/{userId}
  }

  void recommendMovie() async {
    if (selectedFriend.isEmpty) return;
    // Firestore recommendations logic here
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Movie recommended!")),
    );
  }
}
