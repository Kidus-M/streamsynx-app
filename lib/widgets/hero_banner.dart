import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HeroBanner extends StatefulWidget {
  final List<dynamic> items;
  const HeroBanner({super.key, required this.items});

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.items.isNotEmpty) {
      _autoSlide();
    }
  }

  void _autoSlide() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 5));
      if (mounted) {
        setState(() => currentIndex = (currentIndex + 1) % widget.items.length);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final item = widget.items[currentIndex];
    final img = 'https://image.tmdb.org/t/p/original${item['backdrop_path']}';
    final title = item['title'] ?? 'Untitled';
    final overview = item['overview'] ?? '';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      child: Stack(
        key: ValueKey(currentIndex),
        children: [
          CachedNetworkImage(
            imageUrl: img,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 420,
            placeholder: (c, _) => Container(
              color: Colors.black.withOpacity(0.3),
              height: 420,
            ),
          ),
          Container(
            height: 420,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.transparent,
                  Colors.black.withOpacity(0.9),
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFDAA520),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  overview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
