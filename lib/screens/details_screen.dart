import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../data/buddies_repo.dart';
import '../data/deep_links.dart';
import '../data/library_repo.dart';
import '../data/models.dart';
import '../data/tmdb.dart';
import '../player/player_screen.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import '../widgets/poster_card.dart';
import '../widgets/share_poster.dart';
import '../widgets/share_sheet.dart';

/// A title's own screen: what it is, whether to play it, and for a series which
/// episode. Everything on it comes from a single TMDB request.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.item});

  final MediaItem item;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final LibraryRepo _library = LibraryRepo();
  final BuddiesRepo _buddies = BuddiesRepo();
  final ScreenshotController _screenshot = ScreenshotController();

  late Future<MediaDetail> _future;
  List<Episode> _episodes = const [];
  int _season = 1;
  bool _inWatchlist = false;
  bool _favorite = false;
  bool _loadingEpisodes = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MediaDetail> _load() async {
    final detail = await Tmdb.detail(widget.item.id, widget.item.type);

    if (detail.seasons.isNotEmpty) {
      _season = detail.seasons.first.number;
      _episodes = await Tmdb.episodes(widget.item.id, _season);
    }

    final watchlist = await _library.isInWatchlist(detail.item);
    final favorite = await _library.isFavorite(detail.item);
    if (mounted) {
      setState(() {
        _inWatchlist = watchlist;
        _favorite = favorite;
      });
    }
    return detail;
  }

  Future<void> _selectSeason(MediaDetail detail, int number) async {
    if (number == _season || _loadingEpisodes) return;
    setState(() => _loadingEpisodes = true);

    try {
      final episodes = await Tmdb.episodes(widget.item.id, number);
      if (!mounted) return;
      setState(() {
        _season = number;
        _episodes = episodes;
      });
    } on Object {
      if (mounted) showAppSnack(context, 'Could not load that season.');
    } finally {
      if (mounted) setState(() => _loadingEpisodes = false);
    }
  }

  void _play(MediaItem item, {int episode = 1, String? episodeName}) {
    final count = _episodes.isEmpty ? 0 : _episodes.last.number;

    // Root navigator, deliberately: see [PlayerRoute]. Pushing into the tab's own
    // stack left the bottom bar on top of the video.
    unawaited(PlayerRoute.open(
      context,
      item: item,
      season: _season,
      episode: episode,
      episodeCount: count,
      episodeName: episodeName,
      episodes: _episodes,
    ));
  }

  Future<void> _toggleWatchlist(MediaItem item) async {
    final added = await _library.toggleWatchlist(item);
    if (!mounted) return;
    setState(() => _inWatchlist = added);
    showAppSnack(context, added ? 'Added to your watchlist' : 'Removed from watchlist',
        success: added);
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    final added = await _library.toggleFavorite(item);
    if (!mounted) return;
    setState(() => _favorite = added);
    showAppSnack(context, added ? 'Added to favourites' : 'Removed from favourites',
        success: added);
  }

  // --- Sharing ------------------------------------------------------------------

  /// Asks how to share, then does it.
  ///
  /// The link is the default. Handing a messaging app a PNG makes it send a
  /// picture — the caption, and with it the URL, is dropped by most targets —
  /// which is why a shared title used to arrive as something you could only look
  /// at. A bare link unfurls into a card built from the `/open` page's Open Graph
  /// tags, so the recipient gets artwork, a title and something to tap.
  Future<void> _share(MediaItem item) async {
    final choice = await showShareSheet(context, item: item);
    if (choice == null || !mounted) return;

    switch (choice) {
      case ShareChoice.link:
        await Share.share(
          DeepLinks.shareText(item),
          subject: '${item.title} on StreamSynx',
        );
      case ShareChoice.copy:
        await Clipboard.setData(ClipboardData(text: DeepLinks.forItem(item)));
        if (mounted) showAppSnack(context, 'Link copied', success: true);
      case ShareChoice.poster:
        await _sharePoster(item);
    }
  }

  /// Renders the story card and shares it with a link that opens this title in
  /// the app, or the download page for anyone who does not have it yet.
  Future<void> _sharePoster(MediaItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final Uint8List bytes = await _screenshot.captureFromWidget(
        SharePoster(item: item, link: DeepLinks.forItem(item)),
        delay: const Duration(milliseconds: 220),
        pixelRatio: 3,
        context: context,
      );

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/streamsynx_${item.type}_${item.id}.png',
      );
      await file.writeAsBytes(bytes);

      if (mounted) Navigator.of(context).pop();

      await Share.shareXFiles(
        [XFile(file.path)],
        text: DeepLinks.posterText(item),
        subject: '${item.title} on StreamSynx',
      );
    } on Object catch (error) {
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create the poster. $error')),
      );
    }
  }

  Future<void> _recommendToBuddy(MediaItem item) async {
    final friends = await _buddies.watchFriends().first;
    if (!mounted) return;

    if (friends.isEmpty) {
      showAppSnack(context, 'Add a buddy first, then you can recommend titles.');
      return;
    }

    final chosen = await showModalBottomSheet<BuddyProfile>(
      context: context,
      backgroundColor: AppColors.bgSoft,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.md),
              child: Text('Recommend to', style: AppText.headingLg),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: friends.length,
                itemBuilder: (_, index) {
                  final friend = friends[index];
                  return ListTile(
                    onTap: () => Navigator.of(sheetContext).pop(friend),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.surfaceHigh,
                      backgroundImage: NetworkImage(friend.avatarUrl),
                    ),
                    title: Text(friend.username, style: AppText.label),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );

    if (chosen == null || !mounted) return;

    // The sender's own name, not a friend's — the previous build looked this up
    // in the friends map, where it could never appear, so every recommendation
    // arrived from "Anonymous".
    final username = await _buddies.currentUsername();
    await _library.recommend(item: item, toUserId: chosen.uid, fromUsername: username);
    if (mounted) {
      showAppSnack(context, 'Recommended to ${chosen.username}', success: true);
    }
  }

  // --- Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FutureBuilder<MediaDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load this title. ${snapshot.error}',
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final detail = snapshot.data!;
          final item = widget.item.mergedWith(detail.item);

          return CustomScrollView(
            slivers: [
              _DetailHeader(item: item, onPlay: () => _play(item)),
              SliverToBoxAdapter(
                child: _Actions(
                  inWatchlist: _inWatchlist,
                  favorite: _favorite,
                  onWatchlist: () => _toggleWatchlist(item),
                  onFavorite: () => _toggleFavorite(item),
                  onShare: () => _share(item),
                  onRecommend: () => _recommendToBuddy(item),
                ),
              ),
              SliverToBoxAdapter(child: _Overview(item: item)),
              if (detail.seasons.isNotEmpty)
                SliverToBoxAdapter(
                  child: _Episodes(
                    detail: detail,
                    episodes: _episodes,
                    season: _season,
                    loading: _loadingEpisodes,
                    onSeason: (number) => _selectSeason(detail, number),
                    onPlay: (episode) => _play(
                      item,
                      episode: episode.number,
                      episodeName: episode.name,
                    ),
                  ),
                ),
              if (detail.cast.isNotEmpty)
                SliverToBoxAdapter(child: _CastRow(cast: detail.cast)),
              if (detail.recommendations.isNotEmpty)
                SliverToBoxAdapter(
                  child: PosterRail(
                    title: 'More Like This',
                    items: detail.recommendations,
                    onOpen: (other) => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => DetailsScreen(item: other)),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
            ],
          );
        },
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.item, required this.onPlay});

  final MediaItem item;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: MediaQuery.sizeOf(context).height * 0.46,
      pinned: true,
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      leading: const _CircleBack(),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (item.backdropUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: Tmdb.image(item.backdropPath, Tmdb.w780) ?? '',
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
                    AppColors.bg.withValues(alpha: 0.7),
                    AppColors.black(0.25),
                  ],
                  stops: const [0, 0.5, 1],
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
                  Eyebrow(item.kindLabel, color: AppColors.accent),
                  const SizedBox(height: AppSpace.sm),
                  Text(item.title, style: AppText.display, maxLines: 3),
                  const SizedBox(height: AppSpace.sm),
                  Text(item.metaLine(), style: AppText.caption),
                  const SizedBox(height: AppSpace.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text('Play'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBack extends StatelessWidget {
  const _CircleBack();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Material(
        color: AppColors.black(0.45),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          customBorder: const CircleBorder(),
          child: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.inWatchlist,
    required this.favorite,
    required this.onWatchlist,
    required this.onFavorite,
    required this.onShare,
    required this.onRecommend,
  });

  final bool inWatchlist;
  final bool favorite;
  final VoidCallback onWatchlist;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onRecommend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ActionButton(
            icon: inWatchlist ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
            label: inWatchlist ? 'Saved' : 'Watchlist',
            active: inWatchlist,
            onTap: onWatchlist,
          ),
          _ActionButton(
            icon: favorite ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
            label: 'Favourite',
            active: favorite,
            onTap: onFavorite,
          ),
          _ActionButton(
            icon: Icons.ios_share_rounded,
            label: 'Share',
            onTap: onShare,
          ),
          _ActionButton(
            icon: Icons.send_rounded,
            label: 'Recommend',
            onTap: onRecommend,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textSecondary;

    return InkResponse(
      onTap: onTap,
      radius: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label, style: AppText.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    if (item.overview.isEmpty && item.genres.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.genres.isNotEmpty) ...[
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final genre in item.genres) AppChip(label: genre),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
          ],
          if (item.tagline != null && item.tagline!.isNotEmpty) ...[
            Text(
              item.tagline!,
              style: AppText.body.copyWith(
                color: AppColors.accentSoft,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          if (item.overview.isNotEmpty)
            _ExpandableText(text: item.overview),
        ],
      ),
    );
  }
}

/// Synopses run long; three lines with a reveal keeps the fold useful.
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            style: AppText.bodyMuted,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(_expanded ? 'Show less' : 'Read more'),
        ),
      ],
    );
  }
}

class _Episodes extends StatelessWidget {
  const _Episodes({
    required this.detail,
    required this.episodes,
    required this.season,
    required this.loading,
    required this.onSeason,
    required this.onPlay,
  });

  final MediaDetail detail;
  final List<Episode> episodes;
  final int season;
  final bool loading;
  final ValueChanged<int> onSeason;
  final ValueChanged<Episode> onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Episodes'),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            itemCount: detail.seasons.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
            itemBuilder: (_, index) {
              final entry = detail.seasons[index];
              return AppChip(
                label: 'Season ${entry.number}',
                selected: entry.number == season,
                onTap: () => onSeason(entry.number),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(AppSpace.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (episodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: Text('Nothing has aired for this season yet.', style: AppText.bodyMuted),
          )
        else
          for (final episode in episodes)
            _EpisodeTile(episode: episode, onTap: () => onPlay(episode)),
        const SizedBox(height: AppSpace.xl),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.onTap});

  final Episode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = Tmdb.image(episode.stillPath, Tmdb.w342);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.gutter, vertical: AppSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: AppRadius.all(AppRadius.md),
              child: SizedBox(
                width: 128,
                height: 72,
                child: still == null
                    ? const ColoredBox(color: AppColors.surface)
                    : CachedNetworkImage(
                        imageUrl: still,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ColoredBox(color: AppColors.surface),
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: AppColors.surface),
                      ),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${episode.number}. ${episode.name}',
                    style: AppText.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(episode.meta, style: AppText.caption.copyWith(color: AppColors.accent)),
                  if (episode.overview.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      episode.overview,
                      style: AppText.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.play_circle_outline_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.cast});

  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Cast'),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpace.lg),
            itemBuilder: (_, index) {
              final member = cast[index];
              final photo = Tmdb.image(member.profilePath, Tmdb.w185);

              return SizedBox(
                width: 84,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: AppColors.surface,
                      backgroundImage: photo == null ? null : NetworkImage(photo),
                      child: photo == null
                          ? const Icon(Icons.person_rounded, color: AppColors.textSecondary)
                          : null,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      member.name,
                      style: AppText.caption.copyWith(color: AppColors.textPrimary),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      member.character,
                      style: AppText.caption.copyWith(fontSize: 11),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpace.xl),
      ],
    );
  }
}
