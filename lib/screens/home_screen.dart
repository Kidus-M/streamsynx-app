import 'package:flutter/material.dart';
import '../widgets/carousel_section.dart';
import 'watchlist_screen.dart';
import 'history_screen.dart';
import 'buddies_screen.dart';
import 'profile_screen.dart';
import 'SearchScreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 2;

  final List<Widget> _pages = [
    const WatchlistScreen(),
    const HistoryScreen(),
    const HomeContent(),
    const BuddiesScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        backgroundColor: const Color(0xFF282828),
        selectedItemColor: const Color(0xFFDAA520),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Watchlist'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Buddies'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomeContent extends StatelessWidget {
  const HomeContent({super.key});

  void _openSearch(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Top Navbar
          Container(
            color: const Color(0xFF282828),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'StreamSynx',
                  style: TextStyle(
                    color: Color(0xFFDAA520),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => _openSearch(context),
                  icon: const Icon(Icons.search, color: Colors.white),
                ),
              ],
            ),
          ),
          // Content below navbar
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                SizedBox(height: 16),
                CarouselSection(title: 'Trending Movies', type: 'movie', endpoint: 'trending/movie/week'),
                SizedBox(height: 24),
                CarouselSection(title: 'Highest Rated Movies', type: 'movie', endpoint: 'discover/movie'),
                SizedBox(height: 24),
                CarouselSection(title: 'Trending Shows', type: 'tv', endpoint: 'trending/tv/week'),
                SizedBox(height: 24),
                CarouselSection(title: 'Highest Rated Shows', type: 'tv', endpoint: 'discover/tv'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
