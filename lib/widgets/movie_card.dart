import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:animations/animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:blur/blur.dart';

// --- Theme Colors & Constants ---
const Color primary = Color(0xFF121212);
const Color secondary = Color(0xFF1C1C1C);
const Color accent = Color(0xFFDAA520);
const Color textPrimary = Color(0xFFEAEAEA);
const Color textSecondary = Color(0xFFA0A0A0);

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

// --- Movie Card (No changes needed) ---
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
    if(user != null) _checkWatchlist();
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

    return OpenContainer(
      closedElevation: 0,
      openElevation: 0,
      closedColor: Colors.transparent,
      openColor: primary,
      transitionDuration: const Duration(milliseconds: 500),
      transitionType: ContainerTransitionType.fadeThrough,
      closedBuilder: (_, openContainer) => GestureDetector(
        onTap: openContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      poster,
                      height: 300,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) => progress == null ? child : Container(color: secondary),
                      errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.movie, color: textSecondary, size: 40)),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _toggleWatchlist,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isInWatchlist ? accent.withOpacity(0.9) : Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          isInWatchlist ? Icons.check_rounded : Icons.add_rounded,
                          color: isInWatchlist ? primary : textPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 2),
              child: Text(
                title,
                style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (vote > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2.0, left: 2),
                child: Row(
                  children: [
                    const Icon(Icons.star_rate_rounded, color: accent, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      vote.toStringAsFixed(1),
                      style: GoogleFonts.poppins(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      openBuilder: (_, __) => MovieDetailModal(movie: widget.movie),
    );
  }
}

// --- Enhanced Movie Detail Modal ---
class MovieDetailModal extends StatefulWidget {
  final Map<String, dynamic> movie;
  const MovieDetailModal({super.key, required this.movie});

  @override
  State<MovieDetailModal> createState() => _MovieDetailModalState();
}

class _MovieDetailModalState extends State<MovieDetailModal> {
  final user = auth.currentUser;
  final ScreenshotController screenshotController = ScreenshotController();
  bool favorite = false;
  double rating = 0;
  List<Map<String, dynamic>> friends = [];
  String selectedFriend = "";
  Map<String, String> friendNames = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (user == null) return;

    // Load favorites
    final favDoc = await db.collection('favorites').doc(user!.uid).get();
    if (favDoc.exists) {
      final list = List.from(favDoc.data()?['movies'] ?? []);
      setState(() => favorite = list.any((m) => m['id'] == widget.movie['id']));
    }

    // Load friends
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

  // --- Enhanced Share to Instagram Story ---
  Future<void> _shareToInstagramStory() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: accent),
        ),
      );

      // Generate the story image
      final Uint8List? imageBytes = await screenshotController.captureFromWidget(
        Material(
          child: StoryPosterWidget(
            posterUrl: 'https://image.tmdb.org/t/p/w780${widget.movie['poster_path']}',
            title: widget.movie['title'] ?? widget.movie['name'] ?? 'Untitled',
            voteAverage: widget.movie['vote_average']?.toStringAsFixed(1) ?? 'N/A',
            releaseDate: widget.movie['release_date'] ?? widget.movie['first_air_date'] ?? '',
            mediaType: widget.movie['media_type'] ?? 'movie',
          ),
        ),
        delay: const Duration(milliseconds: 200),
        pixelRatio: 3.0, // Higher quality for Instagram
      );

      Navigator.pop(context); // Remove loading indicator

      if (imageBytes == null) {
        throw Exception('Failed to capture image');
      }

      // Save to temporary directory
      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/instagram_story_${DateTime.now().millisecondsSinceEpoch}.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(imageBytes);

      // Share to Instagram
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: 'Check out "${widget.movie['title'] ?? widget.movie['name']}" on StreamSynx! 🎬',
        subject: 'Movie Recommendation',
      );

    } catch (e) {
      Navigator.pop(context); // Remove loading indicator in case of error
      print("Instagram share error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not share to Instagram Story'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // --- Enhanced Watch Now Button ---
  Future<void> _launchWatchURL() async {
    final bool isMovie = widget.movie['media_type'] == 'movie' || widget.movie['title'] != null;
    final String mediaId = widget.movie['id'].toString();

    final String watchUrl = isMovie
        ? 'https://streamsynx.vercel.app/watch?movie_id=$mediaId'
        : 'https://streamsynx.vercel.app/watchTv/$mediaId/1/1';

    if (!await launchUrl(Uri.parse(watchUrl), mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not launch the website'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _recommend() async {
    if (user == null || selectedFriend.isEmpty) return;

    final movieTitle = widget.movie['title'] ?? widget.movie['name'] ?? 'Untitled';
    final ref = db.collection('recommendations').doc(selectedFriend);

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
      SnackBar(
        content: Text('Recommended "$movieTitle" to ${friendNames[selectedFriend] ?? 'friend'}!'),
        backgroundColor: Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );

    setState(() => selectedFriend = "");
  }

  Future<void> _toggleFavorite() async {
    if (user == null) return;

    setState(() => favorite = !favorite);
    final ref = db.collection('favorites').doc(user!.uid);
    final title = widget.movie['title'] ?? widget.movie['name'] ?? 'Untitled';

    final snap = await ref.get();
    List movies = snap.exists ? List.from(snap.data()?['movies'] ?? []) : [];

    if (favorite) {
      movies.add({
        'id': widget.movie['id'],
        'title': title,
        'poster_path': widget.movie['poster_path'],
        'media_type': widget.movie['media_type'] ?? 'movie',
      });
    } else {
      movies.removeWhere((m) => m['id'] == widget.movie['id']);
    }

    await ref.set({'movies': movies});
  }

  @override
  Widget build(BuildContext context) {
    final poster = 'https://image.tmdb.org/t/p/w780${widget.movie['poster_path']}';
    final backdrop = 'https://image.tmdb.org/t/p/w1280${widget.movie['backdrop_path'] ?? widget.movie['poster_path']}';
    final title = widget.movie['title'] ?? widget.movie['name'] ?? 'Untitled';
    final overview = widget.movie['overview'] ?? 'No overview available.';
    final voteAverage = widget.movie['vote_average']?.toStringAsFixed(1) ?? 'N/A';
    final releaseYear = widget.movie['release_date']?.toString().substring(0, 4) ??
        widget.movie['first_air_date']?.toString().substring(0, 4) ?? '';

    return Scaffold(
      backgroundColor: primary,
      body: Screenshot(
        controller: screenshotController,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 200.0,
              backgroundColor: primary,
              pinned: true,
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: textPrimary, size: 20),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.ios_share_rounded, color: textPrimary, size: 20),
                  ),
                  onPressed: _shareToInstagramStory,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(backdrop, fit: BoxFit.cover).blurred(blur: 2, colorOpacity: 0.2),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primary, Colors.transparent, primary],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          stops: [0.0, 1, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    // Title and Rating Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.poppins(
                                  color: textPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                              ),
                              if (releaseYear.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  releaseYear,
                                  style: GoogleFonts.poppins(
                                    color: textSecondary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: primary, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                voteAverage,
                                style: GoogleFonts.poppins(
                                  color: primary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Action Buttons
                    SizedBox(
                      height: 50,
                      child: Row(
                        children: [
                          // Watch Now Button
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _launchWatchURL,
                              icon: const Icon(Icons.play_arrow_rounded, size: 24),
                              label: const Text(
                                "Watch Now",
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Favorite Button
                          SizedBox(
                            width: 50,
                            child: ElevatedButton(
                              onPressed: _toggleFavorite,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: favorite ? accent : secondary,
                                foregroundColor: favorite ? primary : textPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: Icon(
                                favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Share Button
                          SizedBox(
                            width: 50,
                            child: ElevatedButton(
                              onPressed: _shareToInstagramStory,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: secondary,
                                foregroundColor: textPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: const Icon(Icons.ios_share_rounded, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Overview
                    Text(
                      "Overview",
                      style: GoogleFonts.poppins(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      overview,
                      style: GoogleFonts.poppins(
                        color: textSecondary,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Recommendations Section
                    const Divider(color: secondary),
                    const SizedBox(height: 16),
                    Text(
                      "Recommend to Friends",
                      style: GoogleFonts.poppins(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (friends.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: selectedFriend.isEmpty ? null : selectedFriend,
                        dropdownColor: secondary,
                        style: const TextStyle(color: textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Select a friend',
                          labelStyle: const TextStyle(color: textSecondary),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: textSecondary.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: accent),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: secondary.withOpacity(0.5),
                        ),
                        items: friends.map((f) => DropdownMenuItem<String>(
                          value: f['uid'],
                          child: Text(f['username']),
                        )).toList(),
                        onChanged: (v) => setState(() => selectedFriend = v ?? ""),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: selectedFriend.isEmpty ? null : _recommend,
                        icon: const Icon(Icons.send_rounded, color: primary),
                        label: const Text("Send Recommendation"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: secondary.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.people_rounded, color: textSecondary.withOpacity(0.7)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Add friends to share recommendations",
                                style: GoogleFonts.poppins(
                                  color: textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- FIXED Story Poster Widget with Image Loading ---
class StoryPosterWidget extends StatelessWidget {
  final String posterUrl;
  final String title;
  final String voteAverage;
  final String releaseDate;
  final String mediaType;

  const StoryPosterWidget({
    super.key,
    required this.posterUrl,
    required this.title,
    required this.voteAverage,
    required this.releaseDate,
    required this.mediaType,
  });

  Future<void> _launchSite() async {
    final Uri url = Uri.parse('https://streamsynx.vercel.app');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Colors.orange;
    const textPrimary = Colors.white;
    const textSecondary = Colors.white70;
    const secondary = Colors.black87;
    const primary = Colors.white;

    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // maintain Instagram Story 9:16 aspect ratio
        final storyHeight = width * (16 / 9);
        final storyWidth = height * (9 / 16);

        return GestureDetector(
          onTap: _launchSite,
          child: Container(
            width: storyWidth < width ? storyWidth : width,
            height: storyHeight < height ? storyHeight : height,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(posterUrl),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.black.withOpacity(0.4),
                    Colors.black.withOpacity(0.85),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.08,
                  vertical: height * 0.08,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // --- TOP BRANDING ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.movie_rounded, color: accent, size: width * 0.06),
                        SizedBox(width: width * 0.02),
                        Text(
                          'StreamSynx',
                          style: GoogleFonts.poppins(
                            color: textPrimary,
                            fontSize: width * 0.06,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),

                    // --- CENTER POSTER ---
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: width * 0.6,
                          height: height * 0.45,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: accent, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.7),
                                blurRadius: 40,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.network(
                              posterUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  color: secondary,
                                  child: const Center(
                                    child: CircularProgressIndicator(color: accent),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: secondary,
                                  child: const Center(
                                    child: Icon(Icons.movie_rounded,
                                        color: accent, size: 80),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        SizedBox(height: height * 0.02),

                        // --- TITLE ---
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: width * 0.1),
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: textPrimary,
                              fontSize: width * 0.055,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        SizedBox(height: height * 0.02),

                        // --- INFO CHIPS ---
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (year.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  year,
                                  style: GoogleFonts.poppins(
                                    color: textPrimary,
                                    fontSize: width * 0.04,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                mediaType == 'tv' ? 'TV SERIES' : 'MOVIE',
                                style: GoogleFonts.poppins(
                                  color: primary,
                                  fontSize: width * 0.035,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star_rounded,
                                      color: accent, size: width * 0.035),
                                  const SizedBox(width: 6),
                                  Text(
                                    voteAverage,
                                    style: GoogleFonts.poppins(
                                      color: textPrimary,
                                      fontSize: width * 0.035,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // --- BOTTOM WEBSITE TAG ---
                    // Column(
                    //   children: [
                    //     Text(
                    //       'streamsynx.vercel.app',
                    //       style: GoogleFonts.poppins(
                    //         color: accent,
                    //         fontSize: width * 0.025,
                    //         fontWeight: FontWeight.w600,
                    //       ),
                    //     ),
                    //     const SizedBox(height: 6),
                    //     Text(
                    //       'Discover. Watch. Enjoy.',
                    //       style: GoogleFonts.poppins(
                    //         color: textSecondary,
                    //         fontSize: width * 0.04,
                    //         fontWeight: FontWeight.w500,
                    //       ),
                    //     ),
                    //   ],
                    // ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}