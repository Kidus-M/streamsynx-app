import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/library_repo.dart';
import '../data/models.dart';
import '../data/tmdb.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/poster_card.dart';
import 'details_screen.dart';
import 'recommended_screen.dart';
import 'search_screen.dart';

/// One featured title over a stack of rails — the same shape as the site's home.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _rails = <_RailSpec>[
    _RailSpec('Trending Movies', 'trending/movie/week', 'movie'),
    _RailSpec('Trending Series', 'trending/tv/week', 'tv'),
    _RailSpec('Popular Movies', 'movie/popular', 'movie'),
    _RailSpec('Popular Series', 'tv/popular', 'tv'),
    _RailSpec('Top Rated Films', 'movie/top_rated', 'movie'),
    _RailSpec('Top Rated Series', 'tv/top_rated', 'tv'),
  ];

  final LibraryRepo _library = LibraryRepo();

  late Future<Map<String, List<MediaItem>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, List<MediaItem>>> _load() async {
    if (!Tmdb.hasKey) {
      throw const TmdbException('No TMDB key is configured in this build.');
    }

    final results = await Future.wait(
      _rails.map((rail) => Tmdb.list(rail.path, forcedType: rail.type)),
    );
    return {
      for (var i = 0; i < _rails.length; i++) _rails[i].title: results[i],
    };
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future.catchError((_) => <String, List<MediaItem>>{});
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<Map<String, List<MediaItem>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _HomeSkeleton();
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
                  ErrorState(
                    message: '${snapshot.error}',
                    onRetry: _refresh,
                  ),
                ],
              );
            }

            final data = snapshot.data ?? const {};
            final featured = _featuredFrom(data);

            return CustomScrollView(
              slivers: [
                _HomeAppBar(
                  onSearch: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  ),
                  onRecommended: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecommendedScreen()),
                  ),
                ),
                if (featured.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _FeaturedCarousel(items: featured, onOpen: _open),
                  ),
                SliverToBoxAdapter(
                  child: _ContinueWatching(library: _library, onOpen: _open),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final rail = _rails[index];
                      return PosterRail(
                        title: rail.title,
                        items: data[rail.title] ?? const [],
                        onOpen: _open,
                      );
                    },
                    childCount: _rails.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The first few trending films make the hero; anything without a backdrop is
  /// skipped because the carousel is nothing but backdrop.
  List<MediaItem> _featuredFrom(Map<String, List<MediaItem>> data) =>
      (data[_rails.first.title] ?? const <MediaItem>[])
          .where((item) => item.backdropPath != null)
          .take(5)
          .toList(growable: false);
}

class _RailSpec {
  const _RailSpec(this.title, this.path, this.type);

  final String title;
  final String path;
  final String type;
}

class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar({required this.onSearch, required this.onRecommended});

  final VoidCallback onSearch;
  final VoidCallback onRecommended;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      titleSpacing: AppSpace.gutter,
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: AppRadius.all(9),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: AppColors.bg, size: 19),
          ),
          const SizedBox(width: AppSpace.md),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Stream'),
                TextSpan(
                  text: 'Synx',
                  style: TextStyle(color: AppColors.accent),
                ),
              ],
            ),
            style: AppText.headingSm.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: onRecommended,
          icon: const Icon(Icons.auto_awesome_rounded),
          color: AppColors.accent,
          tooltip: 'Recommended for you',
        ),
        IconButton(
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Search',
        ),
        const SizedBox(width: AppSpace.sm),
      ],
    );
  }
}

/// The featured block: full-bleed backdrop, title, meta and a Play affordance.
class _FeaturedCarousel extends StatefulWidget {
  const _FeaturedCarousel({required this.items, required this.onOpen});

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;

  @override
  State<_FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<_FeaturedCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.42;

    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (_, index) => _FeaturedSlide(
              item: widget.items[index],
              onOpen: () => widget.onOpen(widget.items[index]),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.items.length; i++)
              AnimatedContainer(
                duration: AppMotion.fast,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 4,
                width: i == _page ? 18 : 6,
                decoration: BoxDecoration(
                  color: i == _page ? AppColors.accent : AppColors.white(0.2),
                  borderRadius: AppRadius.all(AppRadius.pill),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
      ],
    );
  }
}

class _FeaturedSlide extends StatelessWidget {
  const _FeaturedSlide({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.backdropUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: item.backdropUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const ColoredBox(color: AppColors.surface),
              errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.surface),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AppColors.bg,
                  AppColors.bg.withValues(alpha: 0.75),
                  AppColors.black(0.15),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
          Positioned(
            left: AppSpace.gutter,
            right: AppSpace.gutter,
            bottom: AppSpace.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Eyebrow('Featured', color: AppColors.accent),
                const SizedBox(height: AppSpace.sm),
                Text(
                  item.title,
                  style: AppText.display,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  item.metaLine(),
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.lg),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Watch now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The resume rail. It is a stream so playing something updates it on return.
class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({required this.library, required this.onOpen});

  final LibraryRepo library;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MediaItem>>(
      stream: library.watchHistory(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <MediaItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return PosterRail(
          title: 'Continue Watching',
          items: items.take(12).toList(growable: false),
          onOpen: onOpen,
        );
      },
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 90),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: Skeleton(
            height: MediaQuery.sizeOf(context).height * 0.34,
            radius: AppRadius.lg,
          ),
        ),
        const SizedBox(height: AppSpace.xxl),
        const RailSkeleton(),
        const SizedBox(height: AppSpace.xl),
        const RailSkeleton(),
      ],
    );
  }
}
