import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/carousel_section.dart';
import '../widgets/hero_banner.dart';
import 'watchlist_screen.dart';
import 'history_screen.dart';
import 'buddies_screen.dart';
import 'profile_screen.dart';
import 'SearchScreen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _selectedIndex = 2;
  bool _loading = true;
  bool _error = false;
  List<dynamic> trendingMovies = [];

  final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _fetchHomeData();
  }

  Future<void> _fetchHomeData() async {
    final apiKey = dotenv.env['TMDB_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _error = true;
        _loading = false;
      });
      return;
    }

    try {
      final url = Uri.parse(
          'https://api.themoviedb.org/3/trending/movie/week?api_key=$apiKey&language=en-US');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          trendingMovies = data['results'];
          _loading = false;
        });
      } else {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Home data fetch error: $e');
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final themeText = GoogleFonts.poppins(color: Colors.white);

    final List<Widget> pages = [
      const WatchlistScreen(),
      const HistoryScreen(),
      _loading
          ? const Center(
          child: CircularProgressIndicator(color: Color(0xFFDAA520)))
          : _error
          ? const Center(
          child: Text('⚠️ Failed to load home content',
              style: TextStyle(color: Colors.redAccent)))
          : HomeContent(trendingMovies: trendingMovies),
      const BuddiesScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: pages[_selectedIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              offset: const Offset(0, -2),
              blurRadius: 6,
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          backgroundColor: Colors.transparent,
          selectedItemColor: const Color(0xFFDAA520),
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: themeText.copyWith(fontSize: 12),
          unselectedLabelStyle: themeText.copyWith(fontSize: 12),
          onTap: _onItemTapped,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Watchlist'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Buddies'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class HomeContent extends StatelessWidget {
  final List<dynamic> trendingMovies;
  const HomeContent({super.key, required this.trendingMovies});

  void _openSearch(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Floating Navbar
        SliverAppBar(
          floating: true,
          snap: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF121212).withOpacity(0.9),
                  Colors.transparent
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'StreamSynx',
                style: GoogleFonts.poppins(
                  color: const Color(0xFFDAA520),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: () => _openSearch(context),
              ),
            ],
          ),
        ),

        // Hero Banner
        SliverToBoxAdapter(
          child: HeroBanner(items: trendingMovies),
        ),

        // Carousel sections
        // Carousel sections
        SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: 16),
            const CarouselSection(
                title: 'Trending Movies',
                type: 'movie',
                endpoint: 'trending/movie/week'),
            const SizedBox(height: 32),
            const CarouselSection(
                title: 'Most Popular Movies', // ✅ Changed title
                type: 'movie',
                endpoint: 'discover/movie'), // ✅ Changed endpoint
            const SizedBox(height: 32),
            const CarouselSection(
                title: 'Trending Shows',
                type: 'tv',
                endpoint: 'trending/tv/week'),
            const SizedBox(height: 32),
            const CarouselSection(
                title: 'Most Popular Shows', // ✅ Changed title
                type: 'tv',
                endpoint: 'discover/tv'), // ✅ Changed endpoint
            const SizedBox(height: 32),
          ]),
        ),
      ],
    );
  }
}
