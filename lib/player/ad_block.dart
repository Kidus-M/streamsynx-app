import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Everything that keeps a provider page from behaving like a provider page.
///
/// The free embed hosts monetise with pop-unders, full-page interstitials and
/// click hijacking. Filtering that while the page is on screen is a losing game —
/// one interstitial that gets through owns the whole app. So the primary defence
/// is not to render the page at all (see `stream_resolver.dart`); this file
/// hardens the resolver while it works, and the visible fallback if it fails.
class AdBlock {
  const AdBlock._();

  /// Hosts these providers pull advertising and pop-under scripts from.
  static const blockedHosts = <String>{
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'google-analytics.com', 'googletagmanager.com', 'googletagservices.com',
    'adservice.google.com', 'adnxs.com', 'adsrvr.org', 'rubiconproject.com',
    'pubmatic.com', 'criteo.com', 'criteo.net', 'taboola.com', 'outbrain.com',
    'propellerads.com', 'propellerpops.com', 'onclickalgo.com', 'onclckwbsm.com',
    'popads.net', 'popcash.net', 'popmyads.com', 'poperblocker.com',
    'adsterra.com', 'adsterranet.com', 'highperformanceformat.com',
    'profitableratecpm.com', 'pemsrv.com', 'exoclick.com', 'exosrv.com',
    'juicyads.com', 'trafficjunky.net', 'trafficfactory.biz', 'hilltopads.net',
    'clickadu.com', 'adcash.com', 'mgid.com', 'revcontent.com', 'zedo.com',
    'smartadserver.com', 'sharethrough.com', 'media.net', 'yieldmo.com',
    'bidvertiser.com', 'monetag.com', 'vidoomy.com', 'aniview.com',
    'amung.us', 'histats.com', 'statcounter.com', 'quantserve.com',
    'scorecardresearch.com', 'hotjar.com', 'mixpanel.com', 'segment.io',
    'onesignal.com', 'pushwoosh.com', 'sekindo.com', 'adplayer.pro',
  };

  /// Path fragments that mark an ad request even on a first-party host.
  static const _blockedFragments = <String>[
    '/ads/', '/adserve', '/advert', '/banner', '/popunder', '/popup',
    '/prebid', '/vast', '/vpaid', 'ad_frame', 'adframe', 'adblock-detect',
    '/sponsor',
  ];

  /// Schemes a provider page may use to leave the app entirely.
  static const _blockedSchemes = <String>[
    'intent', 'market', 'tel', 'sms', 'mailto', 'whatsapp', 'fb',
  ];

  static bool shouldBlock(Uri? uri) {
    if (uri == null) return false;

    if (_blockedSchemes.contains(uri.scheme.toLowerCase())) return true;

    final host = uri.host.toLowerCase();
    for (final blocked in blockedHosts) {
      if (host == blocked || host.endsWith('.$blocked')) return true;
    }

    final url = uri.toString().toLowerCase();
    for (final fragment in _blockedFragments) {
      if (url.contains(fragment)) return true;
    }
    return false;
  }

  /// True when [target] belongs to the provider we deliberately opened. Anything
  /// else driving the top-level frame is a redirect the viewer did not ask for.
  static bool isSameProvider(String allowedHost, Uri? target) {
    if (allowedHost.isEmpty || target == null) return false;

    final a = _strip(allowedHost);
    final b = _strip(target.host);
    return a == b || b.endsWith('.$a') || a.endsWith('.$b');
  }

  static String _strip(String host) {
    final lower = host.toLowerCase();
    return lower.startsWith('www.') ? lower.substring(4) : lower;
  }

  static InAppWebViewSettings _base() => InAppWebViewSettings(
        javaScriptEnabled: true,
        // Two of the three popup routes close right here.
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        mediaPlaybackRequiresUserGesture: false,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
      );

  /// Settings for the headless resolver.
  ///
  /// Deliberately carries no content blockers. Filtering here is done by
  /// `shouldInterceptRequest`, which is precise about what it drops; a broad
  /// rule list is the kind of thing that quietly starves the provider's own
  /// player of a script it needed and leaves the page sitting on an error.
  ///
  /// `useOnLoadResource` is what keeps the resolver honest on iOS, where request
  /// interception does not exist at all.
  static InAppWebViewSettings get resolverSettings => _base()
    ..useOnLoadResource = true
    ..useWideViewPort = true
    ..loadWithOverviewMode = true;

  /// The scripts the resolver runs before a provider's own code does.
  ///
  /// `forMainFrameOnly: false` matters more than it looks: these providers put
  /// their real player in an iframe, so the frame that knows the manifest URL is
  /// never the main one.
  static List<UserScript> get resolverScripts => [
        UserScript(
          source: mediaSniffScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
        UserScript(
          source: hardeningScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: false,
        ),
        UserScript(
          source: autoplayScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: false,
        ),
      ];

  /// Settings for the visible fallback, where the page is actually on screen
  /// and therefore worth the extra belt-and-braces filtering.
  static InAppWebViewSettings get webViewSettings =>
      _base()..contentBlockers = contentBlockers;

  /// Hardening for the visible fallback, in every frame and before the page's
  /// own scripts. An interstitial that lives in an iframe is not reachable from
  /// a script evaluated in the main frame after load, which is all this used to
  /// get. No autoplay nudge here — there is a viewer to press play.
  static List<UserScript> get embedScripts => [
        UserScript(
          source: hardeningScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: false,
        ),
      ];

  /// Content-blocker rules. These also apply on iOS, where request
  /// interception is unavailable.
  ///
  /// The trigger matches the *resource* URL. An earlier version used
  /// `ifDomain`, which WebKit matches against the document's domain instead —
  /// it would have blocked everything on an ad host's own page and nothing
  /// anywhere else.
  static List<ContentBlocker> get contentBlockers => [
        for (final host in blockedHosts)
          ContentBlocker(
            trigger: ContentBlockerTrigger(
              urlFilter: '.*${RegExp.escape(host)}.*',
            ),
            action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
          ),
      ];

  /// Injected once a provider page settles. It closes the holes a request filter
  /// cannot: scripted window opening, and elements that exist only to catch a
  /// stray tap.
  static const hardeningScript = r'''
(function(){
  if (window.__synxGuard) return;
  window.__synxGuard = 1;

  window.open = function(){ return null; };
  window.alert = function(){};
  window.confirm = function(){ return false; };
  window.prompt = function(){ return null; };

  var isOverlay = function(el){
    var rect = el.getBoundingClientRect();
    var covers = rect.width >= window.innerWidth * 0.85 &&
                 rect.height >= window.innerHeight * 0.85;
    var style = window.getComputedStyle(el);
    var floating = style.position === 'fixed' || style.position === 'absolute';
    return covers && floating;
  };

  var clean = function(){
    document.querySelectorAll('a[target="_blank"]').forEach(function(a){
      a.removeAttribute('target');
    });
    document.querySelectorAll('a, ins').forEach(function(el){
      if (isOverlay(el)) el.remove();
    });
    document.querySelectorAll('iframe').forEach(function(frame){
      // A full-bleed cross-origin iframe over the player is an interstitial.
      if (!isOverlay(frame)) return;
      var src = frame.getAttribute('src') || '';
      if (src && src.indexOf(location.host) === -1) frame.remove();
    });
  };

  clean();
  new MutationObserver(clean).observe(document.documentElement, {
    childList: true, subtree: true
  });

  document.addEventListener('click', function(e){
    var el = e.target;
    while (el && el.tagName !== 'A') el = el.parentElement;
    if (el && el.host && el.host !== location.host) {
      e.preventDefault();
      e.stopPropagation();
    }
  }, true);
})();
''';

  /// Injected at document start, into every frame, before the provider's own
  /// scripts run.
  ///
  /// Request interception only exists on Android, and even there a provider that
  /// builds its manifest URL inside a worker or hands it to a blob can slip past
  /// it. Hooking the four places a URL can actually enter a player — fetch, XHR,
  /// the media element's `src`, and `setAttribute` — catches the manifest on both
  /// platforms, at the moment the page itself learns about it.
  static const mediaSniffScript = r"""
(function(){
  if (window.__synxSniff) return;
  window.__synxSniff = 1;

  var looksLikeMedia = function(url){
    var s = String(url).toLowerCase();
    if (s.indexOf('.ts?') >= 0 || /\.ts$/.test(s)) return false;
    return s.indexOf('.m3u8') >= 0 || s.indexOf('.mpd') >= 0 ||
           s.indexOf('.mp4') >= 0 || s.indexOf('.mkv') >= 0 ||
           s.indexOf('/manifest') >= 0 || s.indexOf('master.txt') >= 0 ||
           s.indexOf('playlist.txt') >= 0;
  };

  var report = function(url){
    try {
      if (!url) return;
      var raw = String(url);
      if (raw.indexOf('blob:') === 0 || raw.indexOf('data:') === 0) return;
      if (!looksLikeMedia(raw)) return;
      var absolute = new URL(raw, location.href).href;
      var bridge = window.flutter_inappwebview;
      if (bridge && bridge.callHandler) {
        bridge.callHandler('synxMedia', absolute, location.href);
      }
    } catch (e) {}
  };

  var nativeFetch = window.fetch;
  if (nativeFetch) {
    window.fetch = function(input){
      try { report(typeof input === 'string' ? input : (input && input.url)); } catch (e) {}
      return nativeFetch.apply(this, arguments);
    };
  }

  var nativeOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url){
    try { report(url); } catch (e) {}
    return nativeOpen.apply(this, arguments);
  };

  try {
    var descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (descriptor && descriptor.set) {
      Object.defineProperty(HTMLMediaElement.prototype, 'src', {
        configurable: true,
        get: descriptor.get,
        set: function(value){ report(value); return descriptor.set.call(this, value); }
      });
    }
  } catch (e) {}

  var nativeSetAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name, value){
    try {
      var tag = this.tagName;
      if (String(name).toLowerCase() === 'src' && (tag === 'VIDEO' || tag === 'SOURCE')) {
        report(value);
      }
    } catch (e) {}
    return nativeSetAttribute.apply(this, arguments);
  };

  // Some players never touch src directly: they attach a source through a
  // framework that has already resolved it. Polling currentSrc catches those.
  setInterval(function(){
    try {
      var nodes = document.querySelectorAll('video, video source');
      for (var i = 0; i < nodes.length; i++) {
        report(nodes[i].currentSrc || nodes[i].src || nodes[i].getAttribute('src'));
      }
    } catch (e) {}
  }, 800);
})();
""";

  /// Nudges a page into starting playback. Providers commonly wait for a tap
  /// before requesting the manifest, and the resolver has no viewer to supply one.
  static const autoplayScript = r'''
(function(){
  if (window.__synxAutoplay) return;
  window.__synxAutoplay = 1;

  var tap = function(el){
    if (!el) return;
    try { el.click(); } catch (e) {}
    try {
      ['pointerdown','mousedown','mouseup','click'].forEach(function(type){
        el.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true}));
      });
    } catch (e) {}
  };

  var go = function(){
    var video = document.querySelector('video');
    if (video) {
      try { video.muted = true; video.playsInline = true; video.play(); } catch (e) {}
    }
    var selectors = [
      '.play-button', '.play_button', '#play', '.vjs-big-play-button',
      '.jw-icon-display', '.plyr__control--overlaid', '[class*="playBtn"]',
      '[class*="play-btn"]', '[class*="startBtn"]', 'button[aria-label*="lay"]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (el) { tap(el); return; }
    }
    // Nothing recognisable: a tap in the middle is what a viewer would do.
    tap(document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2));
  };

  go();
  [600, 1500, 3000, 5000, 8000, 11000].forEach(function(delay){
    setTimeout(go, delay);
  });
})();
''';
}
