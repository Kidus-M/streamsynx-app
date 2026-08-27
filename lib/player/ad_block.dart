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

  /// WebKit content-blocker rules. Unlike request interception these work on iOS
  /// as well as Android, so the fallback player is filtered on both platforms.
  static List<ContentBlocker> get contentBlockers => [
        for (final host in blockedHosts)
          ContentBlocker(
            trigger: ContentBlockerTrigger(urlFilter: '.*'),
            action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
          ).._withHost(host),
      ];

  /// Settings shared by the resolver and the visible fallback.
  static InAppWebViewSettings get webViewSettings => InAppWebViewSettings(
        javaScriptEnabled: true,
        // Two of the three popup routes close right here.
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        mediaPlaybackRequiresUserGesture: false,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        transparentBackground: true,
        allowsInlineMediaPlayback: true,
        contentBlockers: _hostBlockers(),
      );

  static List<ContentBlocker> _hostBlockers() => [
        for (final host in blockedHosts)
          ContentBlocker(
            trigger: ContentBlockerTrigger(
              urlFilter: '.*',
              ifDomain: ['*$host'],
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

  /// Nudges a page into starting playback. Providers commonly wait for a tap
  /// before requesting the manifest, and the resolver has no viewer to supply one.
  static const autoplayScript = r'''
(function(){
  var go = function(){
    var v = document.querySelector('video');
    if (v) { try { v.muted = true; v.play(); } catch (e) {} }
    var b = document.querySelector('.play, .play-button, [class*=play], button');
    if (b) { try { b.click(); } catch (e) {} }
  };
  go();
  [1200, 3000, 6000].forEach(function(d){ setTimeout(go, d); });
})();
''';
}

extension on ContentBlocker {
  // ignore: unused_element
  void _withHost(String host) {}
}
