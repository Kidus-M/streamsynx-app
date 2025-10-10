import 'package:flutter/material.dart';

class MovieCard extends StatelessWidget {
  final dynamic item;
  const MovieCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final String imageUrl = 'https://image.tmdb.org/t/p/w500${item['poster_path']}';
    final String title = item['title'] ?? item['name'] ?? 'Untitled';

    return GestureDetector(
      onTap: () {},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Image.network(imageUrl, height: 220, fit: BoxFit.cover, width: double.infinity),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              right: 8,
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFEAEAEA),
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
