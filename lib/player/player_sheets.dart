import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/tmdb.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'stream_source.dart';

/// What the playback sheet can come back with.
sealed class PlaybackChoice {
  const PlaybackChoice();
}

class PlaybackFit extends PlaybackChoice {
  const PlaybackFit();
}

class PlaybackLock extends PlaybackChoice {
  const PlaybackLock();
}

class PlaybackSpeed extends PlaybackChoice {
  const PlaybackSpeed(this.value);

  final double value;
}

/// The frame every player sheet uses.
///
/// The player runs landscape, where a sheet that sizes itself to its content
/// happily runs off the bottom of the screen. Capping it at three-quarters of the
/// height and scrolling inside that is what keeps the list reachable — the reason
/// the servers could not be picked before.
Future<T?> _show<T>(
  BuildContext context, {
  required String eyebrow,
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // The player sits on the root navigator; so must anything it opens, or the
    // sheet is clipped to whatever tab happens to be underneath.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.bgSoft,
    barrierColor: AppColors.black(0.6),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetContext) {
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.78;

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Grabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow, style: AppText.eyebrow),
                    const SizedBox(height: AppSpace.xs),
                    Text(title, style: AppText.headingLg),
                  ],
                ),
              ),
              Flexible(child: SingleChildScrollView(child: child)),
              const SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      );
    },
  );
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(top: AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.hairlineStrong,
          borderRadius: AppRadius.all(AppRadius.pill),
        ),
      ),
    );
  }
}

/// Pick a provider. Returns its index, or null if the sheet was dismissed.
Future<int?> showSourceSheet(
  BuildContext context, {
  required List<StreamSource> sources,
  required int selected,
  required bool native,
}) {
  return _show<int>(
    context,
    eyebrow: 'SERVERS',
    title: 'Play from',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < sources.length; i++)
          ListTile(
            onTap: () => Navigator.of(context, rootNavigator: true).pop(i),
            leading: Icon(
              i == selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: i == selected ? AppColors.accent : AppColors.textSecondary,
            ),
            title: Text(sources[i].name, style: AppText.label),
            subtitle: Text(
              i == selected && native
                  ? 'Playing now · native, ad-free'
                  : (sources[i].kind == SourceKind.direct
                      ? 'Native, ad-free'
                      : 'Resolved off-screen'),
              style: AppText.caption,
            ),
            trailing: i == selected
                ? const Icon(Icons.check_rounded,
                    color: AppColors.accent, size: 20)
                : null,
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.sm),
          child: Text(
            'If one stalls, another usually works. Switching keeps your place.',
            style: AppText.caption,
          ),
        ),
      ],
    ),
  );
}

/// Pick an episode without leaving playback. Returns the episode number.
Future<int?> showEpisodeSheet(
  BuildContext context, {
  required List<Episode> episodes,
  required int season,
  required int current,
}) {
  return _show<int>(
    context,
    eyebrow: 'SEASON $season',
    title: 'Episodes',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final episode in episodes)
          ListTile(
            onTap: () =>
                Navigator.of(context, rootNavigator: true).pop(episode.number),
            leading: SizedBox(
              width: 78,
              height: 46,
              child: ClipRRect(
                borderRadius: AppRadius.all(AppRadius.sm),
                child: episode.stillPath == null
                    ? const ColoredBox(color: AppColors.surfaceHigh)
                    : CachedNetworkImage(
                        imageUrl: Tmdb.image(episode.stillPath, Tmdb.w342) ?? '',
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const ColoredBox(color: AppColors.surfaceHigh),
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: AppColors.surfaceHigh),
                      ),
              ),
            ),
            title: Text(
              '${episode.number}. ${episode.name}',
              style: AppText.label.copyWith(
                color: episode.number == current
                    ? AppColors.accent
                    : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(episode.meta, style: AppText.caption, maxLines: 1),
            trailing: episode.number == current
                ? const Icon(Icons.play_arrow_rounded,
                    color: AppColors.accent, size: 20)
                : null,
          ),
      ],
    ),
  );
}

/// Speed, framing and the screen lock — the settings a phone viewer reaches for
/// mid-film, kept out of the way until they do.
Future<PlaybackChoice?> showPlaybackSheet(
  BuildContext context, {
  required double speed,
  required bool fill,
  required bool native,
}) {
  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  return _show<PlaybackChoice>(
    context,
    eyebrow: 'PLAYBACK',
    title: 'Options',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (native) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.gutter, 0, AppSpace.gutter, AppSpace.sm),
            child: Text('Speed', style: AppText.label),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final value in speeds)
                  ChoiceChip(
                    selected: value == speed,
                    onSelected: (_) => Navigator.of(context, rootNavigator: true)
                        .pop(PlaybackSpeed(value)),
                    label: Text(value == 1.0 ? 'Normal' : '${value}x'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          ListTile(
            onTap: () =>
                Navigator.of(context, rootNavigator: true).pop(const PlaybackFit()),
            leading: Icon(
              fill ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              color: AppColors.textSecondary,
            ),
            title: Text(fill ? 'Fit to screen' : 'Zoom to fill', style: AppText.label),
            subtitle: Text(
              fill ? 'Show the whole picture' : 'Crop the black bars',
              style: AppText.caption,
            ),
          ),
        ],
        ListTile(
          onTap: () =>
              Navigator.of(context, rootNavigator: true).pop(const PlaybackLock()),
          leading: const Icon(Icons.lock_outline_rounded,
              color: AppColors.textSecondary),
          title: const Text('Lock screen', style: AppText.label),
          subtitle: const Text(
            'Ignore taps until you unlock it',
            style: AppText.caption,
          ),
        ),
      ],
    ),
  );
}
