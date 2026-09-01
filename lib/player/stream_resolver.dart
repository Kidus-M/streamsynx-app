import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' show Size;

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

  bool get isManifest {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mpd') ||
        lower.contains('/manifest');
  }

  /// `video_player` takes headers as a plain map; the Referer is usually what
  /// decides whether a CDN serves the segment or returns 403.
  Map<String, String> get httpHeaders => {
        ...headers,
        if (userAgent != null) 'User-Agent': userAgent!,
      };

  ResolvedStream withDefaults({required String referer, required String origin}) {
    return ResolvedStream(
      url: url,
      headers: {
        'Referer': referer,
        'Origin': origin,
        ...headers,
      },
      userAgent: userAgent ?? _desktopUserAgent,
    );
  }
}

/// Chrome on Android. Several providers gate the manifest on a browser-looking
/// agent, and `video_player` otherwise sends ExoPlayer's own.
const _desktopUserAgent =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Mobile Safari/537.36';

/// Resolves a provider page down to the video URL underneath it, without ever
/// showing the page.
///
/// This is the answer to the advertising. Filtering a hostile page while it is on
/// screen is a losing game — one interstitial that gets through owns the whole
/// app. So the page is loaded headlessly, purely as a resolver: it is watched
/// from four angles at once — intercepted requests, loaded resources, and the
/// `fetch`/`XHR`/`<video>.src` hooks injected by [AdBlock.mediaSniffScript] — and
/// the first thing that looks like a real manifest wins. Playback then happens in
/// the native player against that URL, where there is no document for an advert
/// to live in.
class StreamResolver {
  StreamResolver();

  /// A manifest is the prize, but plenty of providers serve progressive MP4. MP4
  /// is only accepted after this grace period, because pre-roll advert creatives
  /// are almost always MP4 and almost always arrive first.
  static const _mp4Grace = Duration(seconds: 5);

  HeadlessInAppWebView? _webView;
  Completer<ResolvedStream?>? _completer;
  Timer? _timer;
  DateTime _startedAt = DateTime.now();
  String _host = '';
  String _origin = '';
  String _pageUrl = '';
  bool _settled = false;
  bool _landed = false;

  /// Loads [pageUrl] off-screen and returns the stream it plays, or null if
  /// nothing recognisable turned up before [timeout].
  ///
  /// The view is always torn down before this future completes, so a caller can
  /// simply await it in a loop across sources without leaking a page that is
  /// still making requests.
  Future<ResolvedStream?> resolve(
    String pageUrl, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await dispose();

    _settled = false;
    _startedAt = DateTime.now();
    _pageUrl = pageUrl;
    final parsed = Uri.tryParse(pageUrl);
    _host = parsed?.host ?? '';
    _origin = parsed == null ? '' : '${parsed.scheme}://${parsed.host}';
    _landed = false;

    final completer = Completer<ResolvedStream?>();
    _completer = completer;
    _timer = Timer(timeout, () => _settle(null));

    _webView = HeadlessInAppWebView(
      // A real viewport matters even off-screen: these players check their own
      // dimensions before requesting a manifest, and a zero-sized view never
      // gets past that check.
      initialSize: const Size(1280, 720),
      initialUrlRequest: URLRequest(url: WebUri(pageUrl)),
      initialSettings: AdBlock.resolverSettings,
      initialUserScripts: UnmodifiableListView(AdBlock.resolverScripts),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'synxMedia',
          callback: (args) {
            if (args.isEmpty) return null;
            final url = args.first?.toString();
            final referer = args.length > 1 ? args[1]?.toString() : null;
            _consider(url, referer: referer);
            return null;
          },
        );
      },
      shouldInterceptRequest: (controller, request) async {
        final uri = request.url.uriValue;
        if (AdBlock.shouldBlock(uri)) return _blocked;

        // Everything needed comes off the request itself. Calling back into the
        // controller here would mean awaiting the WebView's own thread from
        // inside a callback that is blocking it.
        _consider(uri.toString(), requestHeaders: request.headers);
        return null;
      },
      onLoadResource: (controller, resource) async {
        // The only media signal iOS gives, and a useful second opinion on
        // Android for requests that never reach the interceptor.
        _consider(resource.url?.toString());
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final target = action.request.url?.uriValue;
        if (AdBlock.shouldBlock(target)) return NavigationActionPolicy.CANCEL;

        // Subframes have to be allowed. These providers load their actual
        // player into an iframe, so cancelling non-main-frame navigation
        // cancels the one thing the resolver is here to find.
        if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;

        // Before the page has ever settled, a main-frame navigation is the
        // provider's own redirect chain — several of them have moved host and
        // now 301 to the new one. Blocking that is blocking the source itself.
        // Once something has loaded, a main-frame navigation is a hijack.
        if (!_landed) {
          _adoptHost(target);
          return NavigationActionPolicy.ALLOW;
        }

        return AdBlock.isSameProvider(_host, target)
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onCreateWindow: (controller, action) async {
        // Refusing the window is what stops a pop-under becoming a screen.
        return false;
      },
      onLoadStop: (controller, url) async {
        _landed = true;
        _adoptHost(url);
        // The user scripts already ran at document start; this re-runs the
        // autoplay nudge for pages that only build their player after load.
        await controller.evaluateJavascript(source: AdBlock.autoplayScript);
      },
    );

    try {
      await _webView!.run();
    } on Object {
      _settle(null);
    }

    final result = await completer.future;
    // Tearing down here rather than inside the callback that produced the hit:
    // disposing a WebView from within one of its own synchronous callbacks is
    // how the resolver used to wedge.
    await dispose();
    return result;
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

    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) completer.complete(null);
  }

  /// Weighs one candidate URL and settles the resolve if it is good enough.
  void _consider(
    String? url, {
    Map<String, String>? requestHeaders,
    String? referer,
  }) {
    if (_settled || url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    if (AdBlock.shouldBlock(uri)) return;
    if (!_isMedia(url)) return;

    final headers = _carryHeaders(requestHeaders);
    final userAgent = headers.remove('User-Agent');
    if (referer != null && referer.isNotEmpty) {
      headers.putIfAbsent('Referer', () => referer);
    }

    _settle(ResolvedStream(
      url: url,
      headers: headers,
      userAgent: userAgent,
    ).withDefaults(
      referer: headers['Referer'] ?? _pageUrl,
      origin: _origin,
    ));
  }

  /// Follows the provider to wherever it has moved, so the same-provider guard
  /// keeps protecting the page the viewer actually ended up on.
  void _adoptHost(Uri? target) {
    if (target == null || target.host.isEmpty) return;
    if (!target.isScheme('http') && !target.isScheme('https')) return;

    _host = target.host;
    _origin = '${target.scheme}://${target.host}';
    _pageUrl = target.toString();
  }

  void _settle(ResolvedStream? stream) {
    if (_settled) return;
    _settled = true;
    _timer?.cancel();

    final completer = _completer;
    if (completer != null && !completer.isCompleted) completer.complete(stream);
  }

  /// True when the URL looks like the actual video rather than a fragment of it.
  bool _isMedia(String url) {
    final lower = url.toLowerCase();

    // Segments are not worth catching: the manifest that lists them is.
    if (lower.endsWith('.ts') || lower.contains('.ts?')) return false;
    if (lower.endsWith('.vtt') || lower.endsWith('.srt')) return false;
    if (lower.endsWith('.jpg') || lower.endsWith('.png')) return false;

    final isManifest = lower.contains('.m3u8') ||
        lower.contains('.mpd') ||
        lower.contains('/manifest') ||
        lower.contains('master.txt');
    if (isManifest) return true;

    final isProgressive = lower.contains('.mp4') || lower.contains('.mkv');
    return isProgressive &&
        DateTime.now().difference(_startedAt) > _mp4Grace;
  }

  static Map<String, String> _carryHeaders(Map<String, String>? headers) {
    if (headers == null) return <String, String>{};
    const wanted = ['Referer', 'Origin', 'Cookie', 'User-Agent'];

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

  static WebResourceResponse get _blocked => WebResourceResponse(
        contentType: 'text/plain',
        data: Uint8List(0),
        statusCode: 200,
        reasonPhrase: 'OK',
      );
}
