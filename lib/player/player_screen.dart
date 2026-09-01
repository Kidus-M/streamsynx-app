import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/library_repo.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chrome.dart';
import 'ad_block.dart';
import 'stream_source.dart';
import 'stream_resolver.dart';

/// Playback.
///
/// Everything that can play, plays natively: real transport controls, resume
/// points, no third-party document on screen. An embedded provider gets there too,
/// after [StreamResolver] has used its page off-screen to find the video
/// underneath it.
///
/// Only when that resolution fails does the provider page itself get shown, with
/// [AdBlock] filtering it. That path is a last resort by design — advertising on
/// these hosts was the worst thing about the previous build, and the reliable way
/// to beat it is to never render their page at all.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    this.season = 1,
    this.episode = 1,
    this.episodeCount = 0,
    this.episodeName,
  });

  final MediaItem item;
  final int season;
  final int episode;
  final int episodeCount;
  final String? episodeName;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _controlsTimeout = Duration(seconds: 4);
  static const _skip = Duration(seconds: 10);

  final LibraryRepo _library = LibraryRepo();
  final StreamResolver _resolver = StreamResolver();

  late List<StreamSource> _sources;
  int _sourceIndex = 0;
  late int _episode;

  VideoPlayerController? _controller;
  String? _fallbackUrl;
  String _fallbackHost = '';

  bool _controlsVisible = true;
  bool _buffering = true;
  String? _status;
  String _shield = 'Ad-free';
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _episode = widget.episode;
    _sources = StreamSource.forItem(widget.item);

    WakelockPlus.enable();
    // Video is a landscape medium: the player rotates into it and stays there,
    // rather than leaving a letterboxed strip in the middle of a tall screen.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    unawaited(_library.recordWatch(widget.item));
    _start(0);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    unawaited(_saveProgress());
    _controller?.removeListener(_onPlayerTick);
    _controller?.dispose();
    unawaited(_resolver.dispose());

    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  // --- Source lifecycle ---------------------------------------------------------

  Future<void> _start(int index) async {
    if (index < 0 || index >= _sources.length) {
      _setStatus('No more sources to try.');
      return;
    }

    await _teardownEngines();
    if (!mounted) return;

    setState(() {
      _sourceIndex = index;
      _buffering = true;
      _status = 'Finding a stream…';
      _controlsVisible = true;
    });

    final source = _sources[index];
    final url = source.urlFor(widget.item, season: widget.season, episode: _episode);

    if (source.kind == SourceKind.direct) {
      await _playNative(ResolvedStream(url: url));
      return;
    }

    final resolved = await _resolver.resolve(url);
    if (!mounted) return;

    if (resolved != null) {
      await _playNative(resolved);
    } else {
      _showFallback(url);
    }
  }

  Future<void> _playNative(ResolvedStream stream) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: stream.httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
    );

    try {
      await controller.initialize();
    } on Object {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _buffering = false;
        _status = 'That source would not play. Try another from Sources.';
      });
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }

    final resumeMs = await _library.progressFor(widget.item, widget.season, _episode);
    if (resumeMs > 0) {
      await controller.seekTo(Duration(milliseconds: resumeMs));
    }
    await controller.play();
    controller.addListener(_onPlayerTick);

    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _buffering = false;
      _shield = 'Ad-free';
      _status = resumeMs > 0 ? 'Resumed from ${_format(Duration(milliseconds: resumeMs))}' : null;
    });
    _scheduleHide();
    if (_status != null) {
      Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _status = null);
      });
    }
  }

  void _showFallback(String url) {
    setState(() {
      _fallbackUrl = url;
      _fallbackHost = Uri.tryParse(url)?.host ?? '';
      _buffering = false;
      _shield = 'Ads filtered';
      _status = 'This source keeps its own player. Ads are filtered, but Sources may work better.';
    });
  }

  Future<void> _teardownEngines() async {
    _hideTimer?.cancel();
    await _saveProgress();

    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onPlayerTick);
    await controller?.dispose();

    await _resolver.dispose();
    if (mounted) setState(() => _fallbackUrl = null);
  }

  // --- Transport ----------------------------------------------------------------

  void _onPlayerTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final value = controller.value;
    if (value.isBuffering != _buffering) {
      setState(() => _buffering = value.isBuffering);
    } else {
      // Repaints the scrubber without rebuilding the whole tree state.
      setState(() {});
    }

    if (value.position >= value.duration && value.duration > Duration.zero) {
      _onFinished();
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    _scheduleHide();
    setState(() {});
  }

  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null) return;

    final target = controller.value.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > controller.value.duration ? controller.value.duration : target);
    await controller.seekTo(clamped);
    _scheduleHide();
  }

  void _onFinished() {
    if (widget.item.isTv && _episode < widget.episodeCount) {
      setState(() => _episode += 1);
      unawaited(_start(_sourceIndex));
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _saveProgress() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    await _library.saveProgress(
      item: widget.item,
      season: widget.season,
      episode: _episode,
      positionMs: controller.value.position.inMilliseconds,
      durationMs: controller.value.duration.inMilliseconds,
    );
  }

  // --- Chrome -------------------------------------------------------------------

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_controller == null) return;
    _hideTimer = Timer(_controlsTimeout, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _setStatus(String message) {
    if (mounted) setState(() => _status = message);
  }

  Future<void> _openSources() async {
    _hideTimer?.cancel();

    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.bgSoft,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('SOURCE', style: AppText.eyebrow),
                  SizedBox(height: AppSpace.xs),
                  Text('Play from', style: AppText.headingLg),
                ],
              ),
            ),
            for (var i = 0; i < _sources.length; i++)
              ListTile(
                onTap: () => Navigator.of(sheetContext).pop(i),
                leading: Icon(
                  i == _sourceIndex ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: i == _sourceIndex ? AppColors.accent : AppColors.textSecondary,
                ),
                title: Text(_sources[i].name, style: AppText.label),
                subtitle: Text(
                  _sources[i].kind == SourceKind.direct
                      ? 'Native, ad-free'
                      : 'Resolved off-screen',
                  style: AppText.caption,
                ),
              ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );

    if (chosen != null && chosen != _sourceIndex) {
      unawaited(_start(chosen));
    } else {
      _scheduleHide();
    }
  }

  // --- Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) => unawaited(_saveProgress()),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildStage(),
              if (_buffering)
                const Center(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _buildControls(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }

    final fallbackUrl = _fallbackUrl;
    if (fallbackUrl != null) {
      return InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(fallbackUrl)),
        initialSettings: AdBlock.webViewSettings,
        shouldInterceptRequest: (controller, request) async =>
            AdBlock.shouldBlock(request.url.uriValue)
                ? WebResourceResponse(
                    contentType: 'text/plain',
                    data: Uint8List(0),
                  )
                : null,
        shouldOverrideUrlLoading: (controller, action) async {
          final target = action.request.url?.uriValue;
          if (AdBlock.shouldBlock(target)) return NavigationActionPolicy.CANCEL;

          // Only the provider may drive the top frame; anything else is a
          // redirect the viewer never asked for. Subframes stay allowed —
          // the provider's player lives in one.
          if (action.isForMainFrame &&
              !AdBlock.isSameProvider(_fallbackHost, target)) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onCreateWindow: (controller, action) async => false,
        onLoadStop: (controller, url) async {
          await controller.evaluateJavascript(source: AdBlock.hardeningScript);
        },
      );
    }

    return const ColoredBox(color: Colors.black);
  }

  Widget _buildControls() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.black(0.75),
            AppColors.black(0.1),
            AppColors.black(0.85),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const Spacer(),
            if (_controller != null) _buildCentreTransport(),
            const Spacer(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.lg, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textPrimary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.title,
                  style: AppText.headingSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _subtitle,
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          ShieldChip(label: _shield),
          IconButton(
            onPressed: _openSources,
            icon: const Icon(Icons.layers_rounded),
            color: AppColors.textPrimary,
            tooltip: 'Sources',
          ),
        ],
      ),
    );
  }

  Widget _buildCentreTransport() {
    final playing = _controller?.value.isPlaying ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundControl(
          icon: Icons.replay_10_rounded,
          onTap: () => _seekBy(-_skip),
        ),
        const SizedBox(width: AppSpace.xxl),
        _RoundControl(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          primary: true,
          onTap: _togglePlay,
        ),
        const SizedBox(width: AppSpace.xxl),
        _RoundControl(
          icon: Icons.forward_10_rounded,
          onTap: () => _seekBy(_skip),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final controller = _controller;
    final status = _status;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, 0, AppSpace.gutter, AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Text(status, style: AppText.caption.copyWith(color: AppColors.accentSoft)),
            ),
          if (controller != null && controller.value.isInitialized) ...[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.white(0.2),
                thumbColor: AppColors.accent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                overlayColor: AppColors.accentAt(0.2),
              ),
              child: Slider(
                value: _sliderValue(controller),
                onChanged: (value) {
                  final target = controller.value.duration * value;
                  controller.seekTo(target);
                  _scheduleHide();
                },
              ),
            ),
            Row(
              children: [
                Text(_format(controller.value.position), style: AppText.caption),
                const Spacer(),
                Text(
                  _sources.isEmpty ? '' : _sources[_sourceIndex].name,
                  style: AppText.caption,
                ),
                const Spacer(),
                Text(_format(controller.value.duration), style: AppText.caption),
              ],
            ),
          ],
          if (widget.item.isTv && _episode < widget.episodeCount)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _onFinished,
                icon: const Icon(Icons.skip_next_rounded, size: 18),
                label: const Text('Next episode'),
              ),
            ),
        ],
      ),
    );
  }

  double _sliderValue(VideoPlayerController controller) {
    final duration = controller.value.duration.inMilliseconds;
    if (duration <= 0) return 0;
    final position = controller.value.position.inMilliseconds;
    return (position / duration).clamp(0.0, 1.0);
  }

  String get _subtitle {
    if (!widget.item.isTv) return widget.item.metaLine();
    final label = 'Season ${widget.season} · Episode $_episode';
    final name = widget.episodeName;
    return (name == null || name.isEmpty) ? label : '$label · $name';
  }

  static String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
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
