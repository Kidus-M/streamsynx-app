import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'ad_block.dart';

/// A playable URL plus the headers its origin will expect to see with it.
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    this.headers = const {},
    this.userAgent,
  });

  final String url;
  final Map<String, String> headers;
  final String? userAgent;

  /// `video_player` takes headers as a plain map; the Referer is usually what
  /// decides whether a CDN serves the segment or returns 403.
  Map<String, String> get httpHeaders => {
        ...headers,
        if (userAgent != null) 'User-Agent': userAgent!,
      };
}

/// Resolves a provider page down to the video URL underneath it, without ever
/// showing the page.
///
/// This is the answer to the advertising. Filtering a hostile page while it is on
/// screen is a losing game — one interstitial that gets through owns the whole
/// app. So the page is loaded headlessly, purely as a resolver: every request it
/// makes is inspected, the media manifest is picked out, and the page is thrown
/// away. Playback then happens in the native player against that URL, where there
/// is no document for an advert to live in.
class StreamResolver {
  StreamResolver();

  /// Long enough for a slow provider to hand over a manifest, short enough not to
  /// strand the viewer on a spinner.
  static const _timeout = Duration(seconds: 22);

  /// A manifest is the prize, but plenty of providers serve progressive MP4. MP4
  /// is only accepted after this grace period, because pre-roll advert creatives
  /// are almost always MP4 and almost always arrive first.
  static const _mp4Grace = Duration(seconds: 6);

  HeadlessInAppWebView? _webView;
  Completer<ResolvedStream?>? _completer;
  Timer? _timer;
  DateTime _startedAt = DateTime.now();
  bool _settled = false;

  /// Loads [pageUrl] off-screen and returns the stream it plays, or null if
  /// nothing recognisable turned up before the timeout.
  Future<ResolvedStream?> resolve(String pageUrl) async {
    await dispose();

    _settled = false;
    _startedAt = DateTime.now();
    final completer = Completer<ResolvedStream?>();
    _completer = completer;

    _timer = Timer(_timeout, () => _settle(null));

    _webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(pageUrl)),
      initialSettings: AdBlock.webViewSettings,
      shouldInterceptRequest: (controller, request) async {
        final uri = request.url.uriValue;
        if (AdBlock.shouldBlock(uri)) return _blocked;

        final candidate = _mediaUrl(uri);
        if (candidate != null) {
          _settle(ResolvedStream(
            url: candidate,
            headers: _carryHeaders(request.headers),
            userAgent: await controller.evaluateJavascript(
              source: 'navigator.userAgent',
            ) as String?,
          ));
        }
        return null;
      },
      shouldOverrideUrlLoading: (controller, action) async {
        // The resolver has no business anywhere but the provider page.
        final isMainFrame = action.isForMainFrame;
        if (!isMainFrame || AdBlock.shouldBlock(action.request.url?.uriValue)) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (controller, action) async {
        // Refusing the window is what stops a pop-under becoming a screen.
        return false;
      },
      onLoadStop: (controller, url) async {
        await controller.evaluateJavascript(source: AdBlock.hardeningScript);
        await controller.evaluateJavascript(source: AdBlock.autoplayScript);
      },
    );

    await _webView!.run();
    return completer.future;
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;

    final webView = _webView;
    _webView = null;
    if (webView != null) {
      try {
        await webView.dispose();
      } on Object {
        // Disposing an already-torn-down view is not worth surfacing.
      }
    }

    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }
    _completer = null;
  }

  void _settle(ResolvedStream? stream) {
    if (_settled) return;
    _settled = true;
    _timer?.cancel();

    final completer = _completer;
    if (completer != null && !completer.isCompleted) completer.complete(stream);

    // The page has served its purpose; tear it down so it stops making requests.
    unawaited(dispose());
  }

  /// @return the URL if it looks like the actual video, otherwise null.
  String? _mediaUrl(Uri? uri) {
    if (uri == null) return null;
    final url = uri.toString();
    final lower = url.toLowerCase();

    // Segments are not worth catching: the manifest that lists them is.
    if (lower.endsWith('.ts') || lower.contains('.ts?')) return null;

    final isManifest = lower.contains('.m3u8') ||
        lower.contains('.mpd') ||
        lower.contains('/manifest');
    if (isManifest) return url;

    final isProgressive = lower.contains('.mp4') || lower.contains('.mkv');
    if (isProgressive && DateTime.now().difference(_startedAt) > _mp4Grace) {
      return url;
    }
    return null;
  }

  static Map<String, String> _carryHeaders(Map<String, String>? headers) {
    if (headers == null) return const {};
    const wanted = ['Referer', 'Origin', 'Cookie'];

    final carried = <String, String>{};
    headers.forEach((key, value) {
      for (final name in wanted) {
        if (key.toLowerCase() == name.toLowerCase() && value.isNotEmpty) {
          carried[name] = value;
        }
      }
    });
    return carried;
  }

  static final _blocked = WebResourceResponse(
    contentType: 'text/plain',
    data: null,
    statusCode: 200,
    reasonPhrase: 'OK',
  );
}
