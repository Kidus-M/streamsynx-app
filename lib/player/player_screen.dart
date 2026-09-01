import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/library_repo.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../theme/app_theme.dart';
import 'ad_block.dart';
import 'player_controls.dart';
import 'player_sheets.dart';
import 'stream_source.dart';
import 'stream_resolver.dart';

/// How the player gets on screen.
///
/// Always the root navigator. The tabs each own a nested navigator, and pushing
/// the player into one of those left the bottom bar sitting over the video and
/// the source sheet trapped inside a five-eighths-height column — which is why
/// the servers could not be reached. A player is a mode, not a page inside a tab.
class PlayerRoute {
  const PlayerRoute._();

  static Future<void> open(
    BuildContext context, {
    required MediaItem item,
    int season = 1,
    int episode = 1,
    int episodeCount = 0,
    String? episodeName,
    List<Episode> episodes = const [],
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: AppMotion.normal,
        reverseTransitionDuration: AppMotion.fast,
        pageBuilder: (_, __, ___) => PlayerScreen(
          item: item,
          season: season,
          episode: episode,
          episodeCount: episodeCount,
          episodeName: episodeName,
          episodes: episodes,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: AppMotion.curve),
          child: child,
        ),
      ),
    );
  }
}

/// Playback.
///
/// Everything that can play, plays natively: real transport controls, resume
/// points, no third-party document on screen. An embedded provider gets there too,
/// after [StreamResolver] has used its page off-screen to find the video
/// underneath it — and if the first provider will not give one up, the next is
/// tried automatically rather than leaving the viewer on a spinner.
///
/// Only when that fails for every candidate does the provider page itself get
/// shown, with [AdBlock] filtering it. That path is a last resort by design —
/// advertising on these hosts was the worst thing about the previous build, and
/// the reliable way to beat it is to never render their page at all.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    this.season = 1,
    this.episode = 1,
    this.episodeCount = 0,
    this.episodeName,
    this.episodes = const [],
  });

  final MediaItem item;
  final int season;
  final int episode;
  final int episodeCount;
  final String? episodeName;
  final List<Episode> episodes;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _Stage { loading, playing, embedded, failed }

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  /// Long enough to read the title, short enough to get out of the way.
  static const _controlsTimeout = Duration(seconds: 4);
  static const _skip = Duration(seconds: 10);

  /// How many providers to try headlessly before showing one of them for real.
  /// Four attempts at fifteen seconds is a minute of spinner; two is thirty
  /// seconds and still covers the common case of one provider being down.
  static const _autoAttempts = 2;
  static const _resolveTimeout = Duration(seconds: 15);

  final LibraryRepo _library = LibraryRepo();
  final StreamResolver _resolver = StreamResolver();

  late List<StreamSource> _sources;
  late int _episode;
  late String? _episodeName;

  int _sourceIndex = 0;
  int _attempt = 0;

  VideoPlayerController? _controller;
  String? _embedUrl;
  String _embedHost = '';
  bool _embedLanded = false;

  _Stage _stage = _Stage.loading;
  String _status = 'Getting things ready…';
  String? _failure;

  bool _controlsVisible = true;
  bool _locked = false;
  bool _fillScreen = false;
  double _speed = 1;
  bool _boosting = false;

  Timer? _hideTimer;
  bool _disposed = false;

  /// Guards the episode change. The controller ticks several times a second, and
  /// the end-of-stream check would otherwise fire the advance on every one of
  /// them until teardown finally detaches the listener.
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _episode = widget.episode;
    _episodeName = widget.episodeName;
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
    unawaited(_startAuto());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();

    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(_persist(controller));
      controller.removeListener(_onControllerChanged);
      unawaited(controller.dispose());
    }
    unawaited(_resolver.dispose());

    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app should not leave audio running, and should not lose the
    // viewer's place if the process is reclaimed while backgrounded.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      final controller = _controller;
      if (controller != null && controller.value.isPlaying) {
        unawaited(controller.pause());
        unawaited(_persist(controller));
      }
    }
  }

  // --- Source lifecycle ---------------------------------------------------------

  /// Tries providers in order until one hands over a real stream, then falls back
  /// to showing the first provider's own player.
  Future<void> _startAuto() async {
    if (_sources.isEmpty) {
      _fail('No provider carries this title yet.');
      return;
    }

    final limit = _autoAttempts < _sources.length ? _autoAttempts : _sources.length;

    for (var index = 0; index < limit; index++) {
      if (_disposed) return;
      _attempt = index + 1;

      final played = await _tryNative(index, of: limit);
      if (played || _disposed) return;
    }

    // Every headless attempt came back empty. Rather than dead-end the viewer,
    // show the provider's own player with the ad filter in front of it.
    if (!_disposed) _showEmbedded(0);
  }

  /// Resolves and plays [index]. Returns true when video is actually running.
  Future<bool> _tryNative(int index, {int of = 1}) async {
    await _teardownPlayback();
    if (_disposed) return false;

    final source = _sources[index];
    _setStage(
      _Stage.loading,
      status: of > 1
          ? 'Finding an ad-free stream · ${source.name} (${index + 1}/$of)'
          : 'Finding an ad-free stream · ${source.name}',
      sourceIndex: index,
    );

    final url = source.urlFor(widget.item, season: widget.season, episode: _episode);
    if (url.isEmpty) return false;

    ResolvedStream? stream;
    if (source.kind == SourceKind.direct) {
      stream = ResolvedStream(url: url);
    } else {
      stream = await _resolver.resolve(url, timeout: _resolveTimeout);
    }
    if (_disposed || stream == null) return false;

    if (mounted) setState(() => _status = 'Starting playback…');
    return _playNative(stream);
  }

  Future<bool> _playNative(ResolvedStream stream) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(stream.url),
      httpHeaders: stream.httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
    );

    try {
      await controller.initialize();
    } on Object {
      await controller.dispose();
      return false;
    }
    if (_disposed || !mounted || !controller.value.isInitialized) {
      await controller.dispose();
      return false;
    }

    final resumeMs = await _library.progressFor(widget.item, widget.season, _episode);
    if (resumeMs > 0 && resumeMs < controller.value.duration.inMilliseconds - 5000) {
      await controller.seekTo(Duration(milliseconds: resumeMs));
    }
    await controller.setPlaybackSpeed(_speed);
    await controller.play();
    controller.addListener(_onControllerChanged);

    if (_disposed || !mounted) {
      await controller.dispose();
      return false;
    }

    setState(() {
      _controller = controller;
      _stage = _Stage.playing;
      _failure = null;
      _status = resumeMs > 0
          ? 'Resumed from ${formatDuration(Duration(milliseconds: resumeMs))}'
          : '';
    });
    _scheduleHide();

    if (_status.isNotEmpty) {
      Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _status = '');
      });
    }
    return true;
  }

  void _showEmbedded(int index) {
    final source = _sources[index];
    final url = source.urlFor(widget.item, season: widget.season, episode: _episode);
    if (url.isEmpty) {
      _fail('${source.name} has nothing for this title.');
      return;
    }

    setState(() {
      _sourceIndex = index;
      _embedUrl = url;
      _embedHost = Uri.tryParse(url)?.host ?? '';
      _embedLanded = false;
      _stage = _Stage.embedded;
      _failure = null;
      _status = '';
      _controlsVisible = true;
    });
    _scheduleHide();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _failure = message;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
  }

  void _setStage(_Stage stage, {String status = '', int? sourceIndex}) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _status = status;
      if (sourceIndex != null) _sourceIndex = sourceIndex;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
  }

  Future<void> _teardownPlayback() async {
    _hideTimer?.cancel();

    final controller = _controller;
    if (controller != null) {
      await _persist(controller);
      controller.removeListener(_onControllerChanged);
      _controller = null;
      await controller.dispose();
    }
    if (mounted) setState(() => _embedUrl = null);
  }

  /// The one entry point for changing provider by hand.
  Future<void> _switchTo(int index) async {
    if (index < 0 || index >= _sources.length) return;

    final played = await _tryNative(index);
    if (played || _disposed) return;
    // A provider the viewer explicitly chose is worth showing even when it will
    // not give up its stream — it is still the thing they asked for.
    if (mounted) _showEmbedded(index);
  }

  // --- Transport ----------------------------------------------------------------

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final value = controller.value;
    if (value.hasError && _stage == _Stage.playing) {
      _fail('The stream stopped. Try another server.');
      return;
    }

    if (value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 400)) {
      _onFinished();
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;

    if (controller.value.isPlaying) {
      await controller.pause();
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    } else {
      await controller.play();
      _scheduleHide();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null) return;
    await _seekTo(controller.value.position + delta);
  }

  Future<void> _seekTo(Duration target) async {
    final controller = _controller;
    if (controller == null) return;

    final duration = controller.value.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);
    await controller.seekTo(clamped);
    _scheduleHide();
  }

  /// Press and hold to run at double speed, the way every phone player now does.
  Future<void> _setBoost(bool on) async {
    final controller = _controller;
    if (controller == null) return;
    // Only starting a boost needs playback to be running. Ending one always has
    // to go through, or a stream that paused mid-hold stays stuck at 2x.
    if (on && !controller.value.isPlaying) return;
    if (_boosting == on) return;

    _boosting = on;
    await controller.setPlaybackSpeed(on ? 2.0 : _speed);
    if (mounted) setState(() {});
  }

  Future<void> _setSpeed(double speed) async {
    _speed = speed;
    await _controller?.setPlaybackSpeed(speed);
    if (mounted) setState(() {});
  }

  void _onFinished() {
    if (_advancing) return;

    if (widget.item.isTv && _episode < widget.episodeCount) {
      unawaited(_playEpisode(_episode + 1));
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _playEpisode(int number) async {
    if (_advancing) return;
    _advancing = true;

    try {
      // Playback is torn down first, on purpose. Tearing down writes the resume
      // point, and it has to be written against the episode that was playing —
      // changing the number first files the old position under the new episode.
      await _teardownPlayback();
      if (_disposed || !mounted) return;

      final match = widget.episodes.where((e) => e.number == number);
      setState(() {
        _episode = number;
        _episodeName = match.isEmpty ? null : match.first.name;
      });

      await _switchTo(_sourceIndex);
    } finally {
      _advancing = false;
    }
  }

  Future<void> _persist(VideoPlayerController controller) async {
    if (!controller.value.isInitialized) return;
    if (controller.value.duration <= Duration.zero) return;

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
    if (_locked) {
      // Locked, a tap only offers the way out; it does not bring the whole
      // overlay back over the picture.
      setState(() => _controlsVisible = true);
      _hideTimer?.cancel();
      _hideTimer = Timer(_controlsTimeout, () {
        if (mounted) setState(() => _controlsVisible = false);
      });
      return;
    }

    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // Nothing is hidden while there is nothing behind it to look at. The embedded
    // fallback is the same case for a different reason: our bar is the only way
    // back out of the provider's page, and its taps go to the page, not to us —
    // so hiding it would strand the viewer.
    if (_stage != _Stage.playing) return;
    if (!(_controller?.value.isPlaying ?? false)) return;

    _hideTimer = Timer(_controlsTimeout, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _openSources() async {
    _hideTimer?.cancel();

    final chosen = await showSourceSheet(
      context,
      sources: _sources,
      selected: _sourceIndex,
      native: _stage == _Stage.playing,
    );

    if (chosen == null) {
      _scheduleHide();
      return;
    }
    unawaited(_switchTo(chosen));
  }

  Future<void> _openEpisodes() async {
    _hideTimer?.cancel();

    final chosen = await showEpisodeSheet(
      context,
      episodes: widget.episodes,
      season: widget.season,
      current: _episode,
    );

    if (chosen == null) {
      _scheduleHide();
      return;
    }
    unawaited(_playEpisode(chosen));
  }

  Future<void> _openMore() async {
    _hideTimer?.cancel();

    final choice = await showPlaybackSheet(
      context,
      speed: _speed,
      fill: _fillScreen,
      native: _stage == _Stage.playing,
    );

    if (choice == null) {
      _scheduleHide();
      return;
    }

    switch (choice) {
      case PlaybackFit():
        setState(() => _fillScreen = !_fillScreen);
      case PlaybackLock():
        setState(() {
          _locked = true;
          _controlsVisible = false;
        });
      case PlaybackSpeed(:final value):
        await _setSpeed(value);
    }
    _scheduleHide();
  }

  // --- Build --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        final controller = _controller;
        if (controller != null) unawaited(_persist(controller));
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildStage(),
            if (_stage == _Stage.playing && _controller != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _controller!,
                builder: (context, value, _) => value.isBuffering && !_controlsVisible
                    ? const Center(
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            PlayerGestureLayer(
              enabled: _stage != _Stage.embedded,
              locked: _locked,
              onTap: _toggleControls,
              onSeekBy: _stage == _Stage.playing ? _seekBy : null,
              onBoost: _stage == _Stage.playing ? _setBoost : null,
              skip: _skip,
            ),
            if (_boosting) const _BoostBadge(),
            _buildOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildStage() {
    final controller = _controller;
    if (_stage == _Stage.playing && controller != null) {
      return VideoStage(controller: controller, fill: _fillScreen);
    }

    final embedUrl = _embedUrl;
    if (_stage == _Stage.embedded && embedUrl != null) {
      return InAppWebView(
        key: ValueKey(embedUrl),
        initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
        initialSettings: AdBlock.webViewSettings,
        initialUserScripts: UnmodifiableListView(AdBlock.embedScripts),
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
          if (action.isForMainFrame) {
            // The provider's own move to a new host happens before anything has
            // loaded; a hijack happens after. Same rule as the resolver.
            if (!_embedLanded) {
              _embedHost = target?.host ?? _embedHost;
              return NavigationActionPolicy.ALLOW;
            }
            if (!AdBlock.isSameProvider(_embedHost, target)) {
              return NavigationActionPolicy.CANCEL;
            }
          }
          return NavigationActionPolicy.ALLOW;
        },
        onCreateWindow: (controller, action) async => false,
        onLoadStop: (controller, url) async {
          _embedLanded = true;
          if (url != null && url.host.isNotEmpty) _embedHost = url.host;
          await controller.evaluateJavascript(source: AdBlock.hardeningScript);
        },
      );
    }

    return const ColoredBox(color: Colors.black);
  }

  Widget _buildOverlay() {
    if (_locked) {
      return LockedOverlay(
        visible: _controlsVisible,
        onUnlock: () {
          setState(() {
            _locked = false;
            _controlsVisible = true;
          });
          _scheduleHide();
        },
      );
    }

    return PlayerControls(
      visible: _controlsVisible,
      stage: switch (_stage) {
        _Stage.loading => ControlsStage.loading,
        _Stage.playing => ControlsStage.playing,
        _Stage.embedded => ControlsStage.embedded,
        _Stage.failed => ControlsStage.failed,
      },
      title: widget.item.title,
      subtitle: _subtitle,
      status: _status,
      failure: _failure,
      shield: _stage == _Stage.embedded ? 'Ads filtered' : 'Ad-free',
      sourceName: _sources.isEmpty ? '' : _sources[_sourceIndex].name,
      attempt: _attempt,
      controller: _controller,
      hasEpisodes: widget.item.isTv && widget.episodes.isNotEmpty,
      hasNextEpisode: widget.item.isTv && _episode < widget.episodeCount,
      skip: _skip,
      onBack: () => Navigator.of(context).maybePop(),
      onTogglePlay: _togglePlay,
      onSeekBy: _seekBy,
      onSeekTo: _seekTo,
      onScrubbing: (active) => active ? _hideTimer?.cancel() : _scheduleHide(),
      onSources: _openSources,
      onEpisodes: _openEpisodes,
      onMore: _openMore,
      onNextEpisode: () => unawaited(_playEpisode(_episode + 1)),
      onRetry: () => unawaited(_switchTo(_sourceIndex)),
    );
  }

  String get _subtitle {
    if (!widget.item.isTv) return widget.item.metaLine();
    final label = 'S${widget.season} · E$_episode';
    final name = _episodeName;
    return (name == null || name.isEmpty) ? label : '$label · $name';
  }
}

/// The badge that confirms a press-and-hold is doing something.
class _BoostBadge extends StatelessWidget {
  const _BoostBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.72),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.black(0.7),
          borderRadius: AppRadius.all(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fast_forward_rounded,
                size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Text('2x speed', style: AppText.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }
}
