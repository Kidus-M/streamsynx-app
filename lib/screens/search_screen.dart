import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/tmdb.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/poster_card.dart';
import 'details_screen.dart';

/// Search, with trending as the resting state so the screen is never empty.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _suggestions = ['Action', 'Comedy', 'Sci-Fi', 'Horror', 'Drama', 'Anime'];

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  List<MediaItem> _results = const [];
  bool _loading = true;
  String _heading = 'Trending now';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _loading = true;
      _error = null;
      _heading = 'Trending now';
    });

    try {
      final items = await Tmdb.list('trending/all/week');
      if (!mounted) return;
      setState(() {
        _results = items;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();

    if (value.trim().isEmpty) {
      _loadTrending();
      return;
    }

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(value.trim()));
  }

  Future<void> _run(String query) async {
    try {
      final items = await Tmdb.search(query);
      // The viewer may have typed on while this was in flight.
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _results = items;
        _loading = false;
        _error = null;
        _heading = items.isEmpty ? 'No matches for "$query"' : 'Results for "$query"';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _open(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Search'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.md),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (value) => _run(value.trim()),
              decoration: InputDecoration(
                hintText: 'Films, series, people',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
            ),
          ),
          if (_controller.text.isEmpty)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
                itemBuilder: (_, index) => AppChip(
                  label: _suggestions[index],
                  onTap: () {
                    _controller.text = _suggestions[index];
                    _run(_suggestions[index]);
                  },
                ),
              ),
            ),
          const SizedBox(height: AppSpace.lg),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return ErrorState(message: '$_error', onRetry: _loadTrending);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing found',
        message: 'Try a different title, or one of the suggestions above.',
        actionLabel: 'Show trending',
        onAction: _loadTrending,
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: _heading),
          PosterGrid(items: _results, onOpen: _open),
          const SizedBox(height: AppSpace.xxl),
        ],
      ),
    );
  }
}
