import '../data/models.dart';

/// Where a title can be played from.
///
/// [SourceKind.direct] is a real video URL the native player owns end to end —
/// no third-party page, so no advertising by construction. [SourceKind.embed] is
/// one of the provider pages the website uses; those bring their own advertising,
/// which is why they are resolved off-screen rather than displayed.
enum SourceKind { direct, embed }

class StreamSource {
  const StreamSource({
    required this.id,
    required this.name,
    required this.kind,
    this.movieTemplate = '',
    this.tvTemplate = '',
  });

  final String id;
  final String name;
  final SourceKind kind;
  final String movieTemplate;
  final String tvTemplate;

  bool supports(MediaItem item) => _templateFor(item).isNotEmpty;

  String urlFor(MediaItem item, {int season = 1, int episode = 1}) {
    final template = _templateFor(item);
    if (template.isEmpty) return '';

    return template
        .replaceAll('{type}', item.isTv ? 'tv' : 'movie')
        .replaceAll('{tmdbId}', '${item.id}')
        .replaceAll('{id}', '${item.id}')
        .replaceAll('{imdbId}', item.imdbId ?? '')
        .replaceAll('{season}', '$season')
        .replaceAll('{episode}', '$episode')
        .replaceAll('{s}', '$season')
        .replaceAll('{e}', '$episode');
  }

  String _templateFor(MediaItem item) {
    final template = item.isTv ? tvTemplate : movieTemplate;
    // A movie-only template is still the right fallback for a series if nothing
    // better is configured.
    if (template.isEmpty && item.isTv) return movieTemplate;
    return template;
  }

  /// Mirrors `stream-sync/lib/embeddedSources.js`. Order matters: the first
  /// source that supports a title is the one tried first.
  static const _builtIn = <StreamSource>[
    StreamSource(
      id: 'vidnest',
      name: 'VidNest',
      kind: SourceKind.embed,
      movieTemplate: 'https://vidnest.fun/movie/{tmdbId}',
      tvTemplate: 'https://vidnest.fun/tv/{tmdbId}/{season}/{episode}',
    ),
    StreamSource(
      id: 'vidking',
      name: 'VidKing',
      kind: SourceKind.embed,
      movieTemplate:
          'https://www.vidking.net/embed/movie/{tmdbId}?color=e9b949&nextEpisode=true&episodeSelector=false',
      tvTemplate:
          'https://www.vidking.net/embed/tv/{tmdbId}/{season}/{episode}?color=e9b949&nextEpisode=true&episodeSelector=false',
    ),
    StreamSource(
      id: 'vidsrc',
      name: 'VidSrc',
      kind: SourceKind.embed,
      // vidsrc-embed.ru only 301s here now. Following that redirect inside the
      // resolver meant a cross-host main-frame navigation, which the guard is
      // there to cancel — so the source is pointed at its real home instead.
      movieTemplate: 'https://vsembed.ru/embed/movie?tmdb={tmdbId}&autoplay=1',
      tvTemplate:
          'https://vsembed.ru/embed/tv?tmdb={tmdbId}&season={season}&episode={episode}&autoplay=1',
    ),
    StreamSource(
      id: 'vidfast',
      name: 'VidFast',
      kind: SourceKind.embed,
      movieTemplate: 'https://vidfast.vc/movie/{tmdbId}',
      tvTemplate: 'https://vidfast.vc/tv/{tmdbId}/{season}/{episode}',
    ),
  ];

  /// Every source that can play the given title, best first.
  static List<StreamSource> forItem(MediaItem item) =>
      _builtIn.where((source) => source.supports(item)).toList(growable: false);
}
