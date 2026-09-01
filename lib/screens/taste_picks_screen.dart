import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/taste_profile.dart';
import '../data/tmdb.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';

/// Four films and four series that say what someone is into.
///
/// This is the input to buddy matching: everything Discover scores is derived
/// from these eight slots, so the screen's whole job is making them quick to
/// fill and obvious when they are not.
class TastePicksScreen extends StatefulWidget {
  const TastePicksScreen({super.key});

  @override
  State<TastePicksScreen> createState() => _TastePicksScreenState();
}

class _TastePicksScreenState extends State<TastePicksScreen> {
  final TasteRepo _repo = TasteRepo();
  final TextEditingController _search = TextEditingController();

  TastePicks _picks = const TastePicks();
  List<MediaItem> _results = const [];
  Timer? _debounce;
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final picks = await _repo.myPicks();
    if (!mounted) return;
    setState(() {
      _picks = picks;
      _loading = false;
    });
    unawaited(_loadPopular());
  }

  Future<void> _loadPopular() async {
    try {
      final items = await Tmdb.list('trending/all/week');
      if (mounted) setState(() => _results = items);
    } on Object {
      // The picker still works through search if trending is unavailable.
    }
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _loadPopular();
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final items = await Tmdb.search(value);
        if (!mounted || _search.text.trim() != value.trim()) return;
        setState(() {
          _results = items;
          _searching = false;
        });
      } on Object {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _toggle(MediaItem item) {
    final pick = TastePick.fromMedia(item);
    final next = _picks.toggle(pick);

    if (next.count == _picks.count && !_picks.contains(item.id, item.type)) {
      showAppSnack(
        context,
        'That is all ${TasteProfile.maxPicksPerType} slots for '
        '${item.isTv ? 'series' : 'films'}. Remove one to swap it out.',
      );
      return;
    }
    setState(() => _picks = next);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _repo.savePicks(_picks);
      if (!mounted) return;
      showAppSnack(context, 'Taste saved. Discover will use it now.', success: true);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) showAppSnack(context, 'Could not save your picks. $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Your taste'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _slots()),
                      SliverToBoxAdapter(child: _searchField()),
                      SliverToBoxAdapter(
                        child: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(AppSpace.xxl),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : _resultsGrid(),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
                    ],
                  ),
                ),
                _saveBar(),
              ],
            ),
    );
  }

  Widget _slots() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick up to ${TasteProfile.maxPicksPerType} films and '
            '${TasteProfile.maxPicksPerType} series you love. Buddies get matched '
            'on what these have in common.',
            style: AppText.bodyMuted,
          ),
          const SizedBox(height: AppSpace.lg),
          _slotRow('Films', _picks.movies, 'movie'),
          const SizedBox(height: AppSpace.lg),
          _slotRow('Series', _picks.shows, 'tv'),
        ],
      ),
    );
  }

  Widget _slotRow(String label, List<TastePick> picks, String type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Eyebrow(label),
            const Spacer(),
            Text(
              '${picks.length}/${TasteProfile.maxPicksPerType}',
              style: AppText.caption.copyWith(
                color: picks.length == TasteProfile.maxPicksPerType
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          height: 118,
          child: Row(
            children: [
              for (var i = 0; i < TasteProfile.maxPicksPerType; i++) ...[
                Expanded(
                  child: i < picks.length
                      ? _filledSlot(picks[i])
                      : const _EmptySlot(),
                ),
                if (i < TasteProfile.maxPicksPerType - 1)
                  const SizedBox(width: AppSpace.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filledSlot(TastePick pick) {
    final poster = Tmdb.image(pick.posterPath, Tmdb.w185);

    return GestureDetector(
      onTap: () => setState(() => _picks = _picks.toggle(pick)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.md),
          border: Border.all(color: AppColors.accentAt(0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (poster != null)
              CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover)
            else
              const ColoredBox(color: AppColors.surface),
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.md),
      child: TextField(
        controller: _search,
        onChanged: _onQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search for something you love',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _search.clear();
                    _onQuery('');
                  },
                ),
        ),
      ),
    );
  }

  Widget _resultsGrid() {
    if (_results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.xxl),
        child: Center(child: Text('Nothing to show.', style: AppText.bodyMuted)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _results.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.sm,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (_, index) {
        final item = _results[index];
        final selected = _picks.contains(item.id, item.type);
        final poster = Tmdb.image(item.posterPath, Tmdb.w185);

        return GestureDetector(
          onTap: () => _toggle(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.all(AppRadius.md),
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.hairline,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null)
                        CachedNetworkImage(imageUrl: poster, fit: BoxFit.cover)
                      else
                        const Icon(Icons.movie_outlined, color: AppColors.textSecondary),
                      if (selected)
                        Container(
                          color: AppColors.black(0.45),
                          child: const Icon(Icons.check_circle_rounded,
                              color: AppColors.accent, size: 28),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.title,
                style: AppText.caption.copyWith(color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _saveBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.gutter),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_picks.count} of ${TasteProfile.totalPickSlots} chosen',
                style: AppText.caption,
              ),
            ),
            FilledButton(
              onPressed: _saving || _picks.count == 0 ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save taste'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white(0.03),
          borderRadius: AppRadius.all(AppRadius.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: const Center(
          child: Icon(Icons.add_rounded, color: AppColors.textSecondary, size: 20),
        ),
      );
}
