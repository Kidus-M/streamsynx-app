import 'package:flutter/material.dart';

import '../data/library_repo.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/poster_card.dart';
import 'details_screen.dart';
import 'search_screen.dart';

/// Titles saved for later, kept live from Firestore.
class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LibraryList(
      eyebrow: 'Your library',
      title: 'Watchlist',
      subtitle: 'Everything you have saved to watch.',
      stream: LibraryRepo().watchWatchlist(),
      emptyIcon: Icons.bookmark_outline_rounded,
      emptyTitle: 'Nothing saved yet',
      emptyMessage: 'Tap the bookmark on any title and it will appear here.',
    );
  }
}

/// The shared frame behind Watchlist and History.
class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.stream,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Stream<List<MediaItem>> stream;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<MediaItem>>(
          stream: stream,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <MediaItem>[];
            final waiting = snapshot.connectionState == ConnectionState.waiting;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: PageHeader(
                    eyebrow: eyebrow,
                    title: title,
                    subtitle: subtitle,
                    trailing: trailing,
                  ),
                ),
                if (waiting)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: emptyIcon,
                      title: emptyTitle,
                      message: emptyMessage,
                      actionLabel: 'Find something',
                      onAction: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: PosterGrid(
                      items: items,
                      onOpen: (item) => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => DetailsScreen(item: item)),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Exposed so History can reuse the same frame.
class LibraryListFrame extends StatelessWidget {
  const LibraryListFrame({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.stream,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Stream<List<MediaItem>> stream;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => _LibraryList(
        eyebrow: eyebrow,
        title: title,
        subtitle: subtitle,
        stream: stream,
        emptyIcon: emptyIcon,
        emptyTitle: emptyTitle,
        emptyMessage: emptyMessage,
        trailing: trailing,
      );
}
