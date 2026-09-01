import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';

/// What the overlay is being drawn over.
enum ControlsStage { loading, playing, embedded, failed }

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// The video itself, either letterboxed or filling the screen.
class VideoStage extends StatelessWidget {
  const VideoStage({super.key, required this.controller, required this.fill});

  final VideoPlayerController controller;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;

    if (!fill) {
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }

    // Zoom-to-fill: the picture is scaled until it covers, and the overflow is
    // clipped. This is the "crop the black bars" toggle every phone player has.
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width <= 0 ? 16 : size.width,
            height: size.height <= 0 ? 9 : size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

/// Everything the viewer can do with a touch that is not aimed at a button.
///
/// Tap toggles the overlay, a double tap on either half jumps, and press-and-hold
/// runs at double speed. These are the three gestures a phone viewer already
/// expects, so they are worth more than any button that could replace them.
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    super.key,
    required this.enabled,
    required this.locked,
    required this.onTap,
    required this.skip,
    this.onSeekBy,
    this.onBoost,
  });

  final bool enabled;
  final bool locked;
  final VoidCallback onTap;
  final Duration skip;
  final ValueChanged<Duration>? onSeekBy;
  final ValueChanged<bool>? onBoost;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  /// -1 for the left ripple, 1 for the right, 0 for none.
  int _ripple = 0;
  int _rippleSeconds = 0;
  Timer? _rippleTimer;

  @override
  void dispose() {
    _rippleTimer?.cancel();
    super.dispose();
  }

  void _handleDoubleTap(Offset position, Size size) {
    final seek = widget.onSeekBy;
    if (seek == null || widget.locked) return;

    final left = position.dx < size.width / 2;
    seek(left ? -widget.skip : widget.skip);

    setState(() {
      if (_ripple == (left ? -1 : 1)) {
        _rippleSeconds += widget.skip.inSeconds;
      } else {
        _ripple = left ? -1 : 1;
        _rippleSeconds = widget.skip.inSeconds;
      }
    });

    _rippleTimer?.cancel();
    _rippleTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _ripple = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      // In the embedded fallback the provider's own player owns the surface, so
      // nothing here may swallow its taps.
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTapDown: (details) => _handleDoubleTap(details.localPosition, size),
          onDoubleTap: () {},
          onLongPressStart: (_) => widget.onBoost?.call(true),
          onLongPressEnd: (_) => widget.onBoost?.call(false),
          onLongPressCancel: () => widget.onBoost?.call(false),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const SizedBox.expand(),
              if (_ripple != 0)
                Align(
                  alignment: _ripple == -1
                      ? const Alignment(-0.55, 0)
                      : const Alignment(0.55, 0),
                  child: _SeekRipple(
                    forward: _ripple == 1,
                    seconds: _rippleSeconds,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SeekRipple extends StatelessWidget {
  const _SeekRipple({required this.forward, required this.seconds});

  final bool forward;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: 1,
      duration: AppMotion.fast,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.black(0.55),
          borderRadius: AppRadius.all(AppRadius.pill),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: AppColors.textPrimary,
              size: 30,
            ),
            const SizedBox(height: 2),
            Text(
              '$seconds seconds',
              style: AppText.caption.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full control overlay: title and servers on top, transport in the middle,
/// scrubber and secondary actions along the bottom.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.visible,
    required this.stage,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.failure,
    required this.shield,
    required this.sourceName,
    required this.attempt,
    required this.controller,
    required this.hasEpisodes,
    required this.hasNextEpisode,
    required this.skip,
    required this.onBack,
    required this.onTogglePlay,
    required this.onSeekBy,
    required this.onSeekTo,
    required this.onScrubbing,
    required this.onSources,
    required this.onEpisodes,
    required this.onMore,
    required this.onNextEpisode,
    required this.onRetry,
  });

  final bool visible;
  final ControlsStage stage;
  final String title;
  final String subtitle;
  final String status;
  final String? failure;
  final String shield;
  final String sourceName;
  final int attempt;
  final VideoPlayerController? controller;
  final bool hasEpisodes;
  final bool hasNextEpisode;
  final Duration skip;

  final VoidCallback onBack;
  final Future<void> Function() onTogglePlay;
  final ValueChanged<Duration> onSeekBy;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<bool> onScrubbing;
  final VoidCallback onSources;
  final VoidCallback onEpisodes;
  final VoidCallback onMore;
  final VoidCallback onNextEpisode;
  final VoidCallback onRetry;

  bool get _isPlaying => stage == ControlsStage.playing;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.normal,
        curve: AppMotion.curve,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The scrim only exists where there is text over the picture, and it
            // never intercepts a touch: the gesture layer underneath does. In the
            // embedded fallback there is no bottom bar to darken behind, and the
            // provider's own controls live down there.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.black(0.78),
                      AppColors.black(0.06),
                      AppColors.black(0.06),
                      AppColors.black(stage == ControlsStage.embedded ? 0 : 0.86),
                    ],
                    stops: const [0, 0.3, 0.62, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: Column(
                children: [
                  _TopBar(
                    title: title,
                    subtitle: subtitle,
                    shield: shield,
                    sourceName: sourceName,
                    onBack: onBack,
                    onSources: onSources,
                    onMore: stage == ControlsStage.embedded ? null : onMore,
                  ),
                  Expanded(child: Center(child: _buildCentre())),
                  if (stage == ControlsStage.playing ||
                      stage == ControlsStage.loading)
                    _BottomBar(
                      controller: _isPlaying ? controller : null,
                      status: status,
                      sourceName: sourceName,
                      hasEpisodes: hasEpisodes,
                      hasNextEpisode: hasNextEpisode,
                      onSeekTo: onSeekTo,
                      onScrubbing: onScrubbing,
                      onEpisodes: onEpisodes,
                      onNextEpisode: onNextEpisode,
                      onSources: onSources,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCentre() {
    switch (stage) {
      case ControlsStage.loading:
        return _LoadingBlock(status: status, attempt: attempt);
      case ControlsStage.failed:
        return _FailureBlock(
          message: failure ?? 'This one would not play.',
          onRetry: onRetry,
          onSources: onSources,
        );
      case ControlsStage.embedded:
        return const SizedBox.shrink();
      case ControlsStage.playing:
        final controller = this.controller;
        if (controller == null) return const SizedBox.shrink();

        // The icon has to follow the engine, not the last tap: playback also
        // stops on its own at the end of a stream or when the buffer runs dry.
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) => _Transport(
            playing: value.isPlaying,
            buffering: value.isBuffering,
            skip: skip,
            onTogglePlay: onTogglePlay,
            onSeekBy: onSeekBy,
          ),
        );
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.shield,
    required this.sourceName,
    required this.onBack,
    required this.onSources,
    required this.onMore,
  });

  final String title;
  final String subtitle;
  final String shield;
  final String sourceName;
  final VoidCallback onBack;
  final VoidCallback onSources;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm, right: AppSpace.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textPrimary,
            tooltip: 'Back',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.headingSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          ShieldChip(label: shield),
          const SizedBox(width: AppSpace.sm),
          // Labelled, not an icon. "Which server am I on, and how do I change it"
          // is the single most common thing a viewer wants from this bar.
          _PillButton(
            icon: Icons.dns_rounded,
            label: sourceName.isEmpty ? 'Servers' : sourceName,
            onTap: onSources,
          ),
          if (onMore != null)
            IconButton(
              onPressed: onMore,
              icon: const Icon(Icons.more_vert_rounded),
              color: AppColors.textPrimary,
              tooltip: 'Playback options',
            ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.playing,
    required this.buffering,
    required this.skip,
    required this.onTogglePlay,
    required this.onSeekBy,
  });

  final bool playing;
  final bool buffering;
  final Duration skip;
  final Future<void> Function() onTogglePlay;
  final ValueChanged<Duration> onSeekBy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RoundControl(
          icon: Icons.replay_10_rounded,
          onTap: () => onSeekBy(-skip),
        ),
        const SizedBox(width: AppSpace.xxl),
        // The spinner replaces the button rather than sitting on top of it, so
        // there is never a play icon that does nothing when tapped.
        if (buffering)
          const SizedBox(
            width: 68,
            height: 68,
            child: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          )
        else
          RoundControl(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            primary: true,
            onTap: () => unawaited(onTogglePlay()),
          ),
        const SizedBox(width: AppSpace.xxl),
        RoundControl(
          icon: Icons.forward_10_rounded,
          onTap: () => onSeekBy(skip),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.status,
    required this.sourceName,
    required this.hasEpisodes,
    required this.hasNextEpisode,
    required this.onSeekTo,
    required this.onScrubbing,
    required this.onEpisodes,
    required this.onNextEpisode,
    required this.onSources,
  });

  final VideoPlayerController? controller;
  final String status;
  final String sourceName;
  final bool hasEpisodes;
  final bool hasNextEpisode;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<bool> onScrubbing;
  final VoidCallback onEpisodes;
  final VoidCallback onNextEpisode;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.md, 0, AppSpace.md, AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.isNotEmpty && controller != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm, left: AppSpace.xs),
              child: Text(
                status,
                style: AppText.caption.copyWith(color: AppColors.accentSoft),
              ),
            ),
          if (controller != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) => Scrubber(
                position: value.position,
                duration: value.duration,
                buffered: value.buffered,
                onSeekTo: onSeekTo,
                onScrubbing: onScrubbing,
              ),
            ),
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              if (hasEpisodes)
                _TextAction(
                  icon: Icons.video_library_rounded,
                  label: 'Episodes',
                  onTap: onEpisodes,
                ),
              if (controller == null)
                _TextAction(
                  icon: Icons.dns_rounded,
                  label: 'Change server',
                  onTap: onSources,
                ),
              const Spacer(),
              if (hasNextEpisode)
                _TextAction(
                  icon: Icons.skip_next_rounded,
                  label: 'Next episode',
                  onTap: onNextEpisode,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The scrub bar, with the buffered range behind the played one.
///
/// A `Slider` was never right here: it has no notion of buffering, its thumb is
/// laid out for a settings row rather than a moving picture, and dragging it
/// seeks on every frame. This one seeks once, on release, and shows the time it
/// would land on while the finger is down.
class Scrubber extends StatefulWidget {
  const Scrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeekTo,
    required this.onScrubbing,
  });

  final Duration position;
  final Duration duration;
  final List<DurationRange> buffered;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<bool> onScrubbing;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  double? _dragFraction;

  double get _fraction {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  double get _bufferedFraction {
    final total = widget.duration.inMilliseconds;
    if (total <= 0 || widget.buffered.isEmpty) return 0;
    final end = widget.buffered.last.end.inMilliseconds;
    return (end / total).clamp(0.0, 1.0);
  }

  void _update(double dx, double width) {
    setState(() => _dragFraction = (dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final shown = _dragFraction ?? _fraction;
    final shownPosition = widget.duration * shown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                widget.onScrubbing(true);
                _update(details.localPosition.dx, width);
              },
              onHorizontalDragUpdate: (details) =>
                  _update(details.localPosition.dx, width),
              onHorizontalDragEnd: (_) {
                final fraction = _dragFraction;
                setState(() => _dragFraction = null);
                widget.onScrubbing(false);
                if (fraction != null) widget.onSeekTo(widget.duration * fraction);
              },
              onTapDown: (details) => _update(details.localPosition.dx, width),
              onTapUp: (_) {
                final fraction = _dragFraction;
                setState(() => _dragFraction = null);
                if (fraction != null) widget.onSeekTo(widget.duration * fraction);
              },
              // A 28pt tall target around a 4pt tall bar: the bar stays fine,
              // the thumb stays catchable.
              child: SizedBox(
                height: 28,
                child: Center(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.white(0.22),
                          borderRadius: AppRadius.all(AppRadius.pill),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: _bufferedFraction,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.white(0.38),
                            borderRadius: AppRadius.all(AppRadius.pill),
                          ),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: shown,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: AppRadius.all(AppRadius.pill),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment(shown * 2 - 1, 0),
                        child: Container(
                          width: _dragFraction == null ? 12 : 16,
                          height: _dragFraction == null ? 12 : 16,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.black(0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: Row(
            children: [
              Text(formatDuration(shownPosition), style: AppText.caption),
              const Spacer(),
              Text(
                '−${formatDuration(widget.duration - shownPosition)}',
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.status, required this.attempt});

  final String status;
  final int attempt;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          status.isEmpty ? 'Loading…' : status,
          style: AppText.label,
          textAlign: TextAlign.center,
        ),
        if (attempt > 1) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            'The first server did not answer. Trying the next one.',
            style: AppText.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _FailureBlock extends StatelessWidget {
  const _FailureBlock({
    required this.message,
    required this.onRetry,
    required this.onSources,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.textSecondary, size: 34),
          const SizedBox(height: AppSpace.md),
          Text(message, style: AppText.label, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.lg),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
              const SizedBox(width: AppSpace.md),
              FilledButton.icon(
                onPressed: onSources,
                icon: const Icon(Icons.dns_rounded, size: 18),
                label: const Text('Change server'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What is left on screen once the controls are locked away.
class LockedOverlay extends StatelessWidget {
  const LockedOverlay({super.key, required this.visible, required this.onUnlock});

  final bool visible;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.normal,
        child: SafeArea(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpace.lg),
              child: RoundControl(
                icon: Icons.lock_rounded,
                onTap: onUnlock,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoundControl extends StatelessWidget {
  const RoundControl({
    super.key,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final size = primary ? 68.0 : 52.0;

    return Material(
      color: primary ? AppColors.accent : AppColors.black(0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: primary ? 38 : 26,
            color: primary ? AppColors.bg : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.black(0.45),
      borderRadius: AppRadius.all(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.all(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.accent),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  label,
                  style: AppText.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
