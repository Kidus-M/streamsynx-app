import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/tmdb.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The card that gets rendered to an image and shared to a story.
///
/// It is sized 1080x1920 so it lands on an Instagram or WhatsApp story without
/// being recropped, and it carries the link in readable type: a story image is
/// not tappable for most accounts, so the URL has to survive being looked at
/// rather than clicked.
class SharePoster extends StatelessWidget {
  const SharePoster({super.key, required this.item, required this.link});

  final MediaItem item;

  /// The smart link — opens this title in the app, or the download page.
  final String link;

  /// Story canvas, at a third of full resolution; captured at pixelRatio 3.
  static const _width = 360.0;
  static const _height = 640.0;

  @override
  Widget build(BuildContext context) {
    final poster = Tmdb.image(item.posterPath, Tmdb.w500);
    final backdrop = Tmdb.image(item.backdropPath, Tmdb.w780);

    return MediaQuery(
      // Captured off-stage, so it must not inherit the device's text scaling.
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: _width,
          height: _height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A blurred backdrop behind the poster gives the card depth without
              // needing a design asset per title.
              if (backdrop != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: CachedNetworkImage(
                    imageUrl: backdrop,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const ColoredBox(color: AppColors.bg),
                    errorWidget: (_, __, ___) => const ColoredBox(color: AppColors.bg),
                  ),
                )
              else
                const ColoredBox(color: AppColors.bg),

              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.bg.withValues(alpha: 0.82),
                      AppColors.bg.withValues(alpha: 0.94),
                      AppColors.bg,
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Brand(),
                    const Spacer(),
                    if (poster != null)
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.all(AppRadius.lg),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.black(0.6),
                                blurRadius: 40,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: CachedNetworkImage(
                            imageUrl: poster,
                            width: 200,
                            height: 300,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                const SizedBox(width: 200, height: 300),
                            errorWidget: (_, __, ___) =>
                                const SizedBox(width: 200, height: 300),
                          ),
                        ),
                      ),
                    const SizedBox(height: 26),
                    Text(
                      item.title,
                      style: AppText.display.copyWith(fontSize: 27, height: 1.1),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item.rating > 0) ...[
                          const Icon(Icons.star_rounded,
                              color: AppColors.accent, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            item.rating.toStringAsFixed(1),
                            style: AppText.label.copyWith(fontSize: 13),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            [item.kindLabel, item.year]
                                .where((part) => part.isNotEmpty)
                                .join('  ·  '),
                            style: AppText.caption.copyWith(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _LinkCallout(link: link),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: AppRadius.all(10),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: AppColors.bg, size: 20),
        ),
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Stream'),
              TextSpan(text: 'Synx', style: TextStyle(color: AppColors.accent)),
            ],
          ),
          style: AppText.headingSm.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// The call to action. Deliberately spells out both outcomes, because the person
/// receiving this may not have the app.
class _LinkCallout extends StatelessWidget {
  const _LinkCallout({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    final display = link.replaceFirst(RegExp(r'^https?://'), '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white(0.05),
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: AppColors.accentAt(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WATCH IT ON STREAMSYNX', style: AppText.eyebrow),
          const SizedBox(height: 8),
          Text(
            display,
            style: AppText.label.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            'Opens in the app · Or get it for free',
            style: AppText.caption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
