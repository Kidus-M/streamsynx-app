import 'package:flutter/material.dart';

class StatsCard extends StatelessWidget {
  final String title;
  final String value;

  const StatsCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 13,
                  fontWeight: FontWeight.w400)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFFDAA520),
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
