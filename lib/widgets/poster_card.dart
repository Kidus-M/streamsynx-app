import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_chrome.dart';

/// The poster card, ported from the web `MinimalCard`: 2:3 artwork with a
/// hairline edge, a rating badge, and the caption underneath so the artwork
/// itself stays clean.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 132,
    this.onSave,
    this.saved = false,
  });

  static const aspect = 2 / 3;

  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  final VoidCallback? onSave;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final height = width / aspect;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Artwork(
            item: item,
            width: width,
            height: height,
            onTap: onTap,
            onSave: onSave,
            saved: saved,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            item.title,
            style: AppText.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            item.caption,
            style: AppText.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.item,
    required this.width,
    required this.height,
    required this.onTap,
    required this.onSave,
    required this.saved,
  });

  final MediaItem item;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onSave;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.all(AppRadius.md),
          border: Border.all(color: AppColors.hairline),
          boxShadow: AppDecoration.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.posterUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: item.posterUrl,
                fit: BoxFit.cover,
                fadeInDuration: AppMotion.normal,
                placeholder: (_, __) => const ColoredBox(color: AppColors.surface),
                errorWidget: (_, __, ___) => const _PosterFallback(),
              )
            else
              const _PosterFallback(),

            if (item.rating > 0)
              Positioned(
                top: AppSpace.sm,
                left: AppSpace.sm,
                child: _RatingBadge(rating: item.rating),
              ),

            if (onSave != null)
              Positioned(
                top: AppSpace.xs,
                right: AppSpace.xs,
                child: _SaveButton(saved: saved, onTap: onSave!),
              ),
          ],
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surface, AppColors.bg],
          ),
        ),
        child: Center(
          child: Icon(Icons.movie_outlined, color: AppColors.textSecondary, size: 28),
        ),
      );
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.black(0.65),
        borderRadius: AppRadius.all(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 12, color: AppColors.accent),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: AppText.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: saved ? AppColors.accent : AppColors.black(0.6),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            saved ? Icons.check_rounded : Icons.add_rounded,
            size: 17,
            color: saved ? AppColors.bg : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// A titled horizontal row of poster cards.
class PosterRail extends StatelessWidget {
  const PosterRail({
    super.key,
    required this.title,
    required this.items,
    required this.onOpen,
    this.action,
    this.cardWidth = 132,
  });

  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final Widget? action;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, action: action),
        SizedBox(
          height: cardWidth / PosterCard.aspect + 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, index) => PosterCard(
              item: items[index],
              width: cardWidth,
              onTap: () => onOpen(items[index]),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
      ],
    );
  }
}

/// A wrapped grid of poster cards, sized from the available width rather than a
/// fixed column count so it holds up on phones and tablets alike.
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final EdgeInsets padding;

  static const _target = 132.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - padding.horizontal;
        final columns = (available / (_target + AppSpace.md)).floor().clamp(2, 6);
        final width = (available - AppSpace.md * (columns - 1)) / columns;

        return GridView.builder(
          padding: padding,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpace.xl,
            crossAxisSpacing: AppSpace.md,
            childAspectRatio: width / (width / PosterCard.aspect + 46),
          ),
          itemBuilder: (_, index) => PosterCard(
            item: items[index],
            width: width,
            onTap: () => onOpen(items[index]),
          ),
        );
      },
    );
  }
}
