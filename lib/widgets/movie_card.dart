import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:blur/blur.dart';
import 'package:animations/animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

const Color primary = Color(0xFF121212);
const Color secondary = Color(0xFF1C1C1C);
const Color accent = Color(0xFFDAA520);
const Color textPrimary = Color(0xFFEAEAEA);
const Color textSecondary = Color(0xFFA0A0A0);

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

class MovieCard extends StatefulWidget {
  final Map<String, dynamic> movie;
  const MovieCard({super.key, required this.movie});

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  bool isInWatchlist = false;
  final user = auth.currentUser;

  @override
  void initState() {
    super.initState();
    _checkWatchlist();
  }

  Future<void> _checkWatchlist() async {
    if (user == null) return;
    final ref = db.collection('watchlists').doc(user!.uid);
    final snap = await ref.get();
    if (!snap.exists) return;
    final items = List.from(snap.data()?['items'] ?? []);
    final found = items.any((i) =>
    i['id'] == widget.movie['id'] &&
        i['media_type'] == (widget.movie['media_type'] ?? 'movie'));
    setState(() => isInWatchlist = found);
  }

  Future<void> _toggleWatchlist() async {
    if (user == null) return;
    final ref = db.collection('watchlists').doc(user!.uid);

    final item = {
      'id': widget.movie['id'],
      'title': widget.movie['title'] ?? widget.movie['name'],
      'poster_path': widget.movie['poster_path'],
      'media_type': widget.movie['media_type'] ?? 'movie',
    };

    final wasAdded = isInWatchlist;
    setState(() => isInWatchlist = !wasAdded);

    final docSnap = await ref.get();
    try {
      if (wasAdded) {
        if (docSnap.exists) {
          final items = List.from(docSnap.data()?['items'] ?? []);
          items.removeWhere((i) =>
          i['id'] == item['id'] && i['media_type'] == item['media_type']);
          await ref.update({'items': items});
        }
      } else {
        if (docSnap.exists) {
          await ref.update({'items': FieldValue.arrayUnion([item])});
        } else {
          await ref.set({'items': [item]});
        }
      }
    } catch (e) {
      setState(() => isInWatchlist = wasAdded);
      print("Watchlist error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final poster = 'https://image.tmdb.org/t/p/w500${widget.movie['poster_path']}';
    final title = widget.movie['title'] ?? widget.movie['name'] ?? 'Untitled';
    final vote = widget.movie['vote_average'] ?? 0.0;
    final genres = (widget.movie['genre_names'] ?? []).take(2).join(', ');

    return OpenContainer(
      closedElevation: 0,
      openElevation: 0,
      closedColor: Colors.transparent,
      openColor: Colors.transparent,
      transitionType: ContainerTransitionType.fadeThrough,
      closedBuilder: (_, open) => Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(poster, height: 220, width: double.infinity, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _toggleWatchlist,
              child: Container(
                decoration: BoxDecoration(
                  color: isInWatchlist ? accent.withOpacity(0.9) : Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(6),
                child: Icon(isInWatchlist ? Icons.check : Icons.add, color: isInWatchlist ? textPrimary : accent, size: 18),
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    if (vote > 0)
                      Row(children: [
                        const Icon(Icons.star, color: accent, size: 12),
                        const SizedBox(width: 2),
                        Text(vote.toStringAsFixed(1), style: TextStyle(color: textPrimary, fontSize: 12)),
                        const SizedBox(width: 6),
                      ]),
                    Flexible(
                        child: Text(genres, style: TextStyle(color: textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis))
                  ],
                )
              ],
            ),
          ),
        ],
      ),
      openBuilder: (_, __) => MovieDetailModal(movie: widget.movie),
    );
  }
}

class MovieDetailModal extends StatefulWidget {
  final Map<String, dynamic> movie;
  const MovieDetailModal({super.key, required this.movie});

  @override
  State<MovieDetailModal> createState() => _MovieDetailModalState();
}

class _MovieDetailModalState extends State<MovieDetailModal> {
  bool favorite = false;
  double rating = 0;
  List<Map<String, dynamic>> friends = [];
  String selectedFriend = "";
  final user = auth.currentUser;
  Map<String, String> friendNames = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (user == null) return;
    final favDoc = await db.collection('favorites').doc(user!.uid).get();
    if (favDoc.exists) {
      final list = List.from(favDoc.data()?['movies'] ?? []);
      setState(() => favorite = list.any((m) => m['id'] == widget.movie['id']));
    }
    final fDoc = await db.collection('friends').doc(user!.uid).get();
    if (fDoc.exists) {
      final ids = List<String>.from(fDoc.data()?['friends'] ?? []);
      final fetched = await Future.wait(ids.map((id) async {
        final u = await db.collection('users').doc(id).get();
        if (u.exists) {
          friendNames[id] = u.data()?['username'] ?? 'Unknown';
          return {'uid': id, 'username': friendNames[id]};
        }
        return null;
      }));
      setState(() => friends = fetched.whereType<Map<String, dynamic>>().toList());
    }
  }

  Future<void> _recommend() async {
    if (user == null || selectedFriend.isEmpty) return;

    final ref = db.collection('recommendations').doc(selectedFriend);

    // Use title if available, otherwise fallback to name (TV shows)
    final movieTitle = widget.movie['title'] ?? widget.movie['name'] ?? 'Untitled';

    final data = {
      'id': widget.movie['id'],
      'title': movieTitle,
      'poster_path': widget.movie['poster_path'],
      'recommendedBy': user!.uid,
      'recommendedByUsername': friendNames[user!.uid] ?? 'Anonymous',
      'recommendedAt': DateTime.now().toIso8601String(),
      'type': widget.movie['media_type'] ?? 'movie',
    };

    final snap = await ref.get();
    List movies = snap.exists ? List.from(snap.data()?['movies'] ?? []) : [];
    movies.add(data);
    await ref.set({'movies': movies});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recommended "$movieTitle" to ${friendNames[selectedFriend] ?? 'friend'}!')),
    );

    setState(() => selectedFriend = "");
  }


  Future<void> _sharePoster() async {
    final posterUrl = 'https://image.tmdb.org/t/p/w500${widget.movie['poster_path']}';
    final response = await http.get(Uri.parse(posterUrl));
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/poster.jpg');
    await file.writeAsBytes(response.bodyBytes);
    await Share.shareXFiles([XFile(file.path)],
        text: 'Check out "${widget.movie['title']}" on StreamSynx!');
  }

  @override
  Widget build(BuildContext context) {
    final poster = 'https://image.tmdb.org/t/p/w500${widget.movie['poster_path']}';
    final title = widget.movie['title'] ?? widget.movie['name'] ?? 'Untitled';
    final overview = widget.movie['overview'] ?? '';

    return Scaffold(
      backgroundColor: primary,
      body: Stack(
        children: [
          Image.network(poster, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
              .blurred(blur: 15, colorOpacity: 0.6),
          Container(color: Colors.black.withOpacity(0.45)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(icon: const Icon(Icons.close, color: textPrimary), onPressed: () => Navigator.pop(context)),
                      IconButton(icon: const Icon(Icons.share, color: accent), onPressed: _sharePoster),
                    ],
                  ),
                  Center(child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(poster, height: 300, fit: BoxFit.cover))),
                  const SizedBox(height: 16),
                  Text(title, style: GoogleFonts.poppins(color: textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(overview, style: GoogleFonts.poppins(color: textSecondary, fontSize: 14)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      IconButton(icon: Icon(favorite ? Icons.favorite : Icons.favorite_border, color: accent), onPressed: () async {
                        setState(() => favorite = !favorite);
                        final ref = db.collection('favorites').doc(user!.uid);
                        final snap = await ref.get();
                        List movies = snap.exists ? List.from(snap.data()?['movies'] ?? []) : [];
                        if (favorite) {
                          movies.add({'id': widget.movie['id'], 'title': title, 'poster_path': widget.movie['poster_path']});
                        } else {
                          movies.removeWhere((m) => m['id'] == widget.movie['id']);
                        }
                        await ref.set({'movies': movies});
                      }),
                      const Text("Favorite", style: TextStyle(color: textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text("Your Rating:", style: TextStyle(color: textSecondary)),
                  Row(
                    children: List.generate(5, (i) {
                      final val = (i + 1) * 2;
                      return IconButton(
                        icon: Icon(val <= rating ? Icons.star : Icons.star_border, color: accent),
                        onPressed: () => setState(() => rating = val.toDouble()),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedFriend.isEmpty ? null : selectedFriend,
                    dropdownColor: secondary,
                    style: const TextStyle(color: textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Recommend to',
                      labelStyle: const TextStyle(color: textSecondary),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: textSecondary.withOpacity(0.3))),
                    ),
                    items: friends.map((f) => DropdownMenuItem<String>(value: f['uid'], child: Text(f['username']))).toList(),
                    onChanged: (v) => setState(() => selectedFriend = v ?? ""),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: selectedFriend.isEmpty ? null : _recommend,
                    icon: const Icon(Icons.send, color: primary),
                    style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: primary),
                    label: const Text("Send Recommendation"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
