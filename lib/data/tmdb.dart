import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// TMDB v3 client.
///
/// The previous build scattered raw `http.get` calls with hand-built URLs across
/// the screens; this keeps the key, the base URL and the JSON shape in one place.
class Tmdb {
  const Tmdb._();

  static const w185 = 'https://image.tmdb.org/t/p/w185';
  static const w342 = 'https://image.tmdb.org/t/p/w342';
  static const w500 = 'https://image.tmdb.org/t/p/w500';
  static const w780 = 'https://image.tmdb.org/t/p/w780';
  static const w1280 = 'https://image.tmdb.org/t/p/w1280';

  static const _host = 'api.themoviedb.org';
  static const _pageLimit = 24;

  static String get _key => dotenv.env['TMDB_API_KEY'] ?? '';

  static bool get hasKey => _key.trim().isNotEmpty;

  static String? image(String? path, String size) =>
      (path == null || path.isEmpty) ? null : '$size$path';

  static Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> params = const {},
  }) async {
    final uri = Uri.https(_host, '/3/$path', {
      'api_key': _key,
      'language': 'en-US',
      ...params,
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw TmdbException('TMDB returned HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// A results list, filtered to entries that actually have artwork to show.
  static Future<List<MediaItem>> list(String path, {String? forcedType}) async {
    final data = await _get(path);
    final results = data['results'];
    if (results is! List) return const [];

    final items = <MediaItem>[];
    for (final entry in results) {
      if (items.length >= _pageLimit) break;
      if (entry is! Map<String, dynamic>) continue;
      final item = MediaItem.fromJson(entry, forcedType: forcedType);
      if (item != null && item.posterPath != null) items.add(item);
    }
    return items;
  }

  /// One request for everything a detail screen needs — credits and
  /// recommendations fold into the same call, which keeps a browse session well
  /// inside TMDB's rate limit.
  static Future<MediaDetail> detail(int id, String type) async {
    final json = await _get(
      '$type/$id',
      params: const {
        'append_to_response': 'external_ids,images,credits,recommendations',
        'include_image_language': 'en,null',
      },
    );

    var item = MediaItem.fromJson(json, forcedType: type);
    if (item == null) throw TmdbException('Unexpected payload for $type/$id');
    item = item.copyWithLogo(_firstLogo(json['images']));

    return MediaDetail(
      item: item,
      cast: _cast(json['credits']),
      recommendations: _recommendations(json['recommendations'], type),
      seasons: type == 'tv' ? _seasons(json['seasons']) : const [],
    );
  }

  static Future<List<Episode>> episodes(int tvId, int season) async {
    final json = await _get('tv/$tvId/season/$season');
    final episodes = json['episodes'];
    if (episodes is! List) return const [];

    return episodes
        .whereType<Map<String, dynamic>>()
        .map(Episode.fromJson)
        .where((episode) => episode.hasAired)
        .toList(growable: false);
  }

  static Future<List<MediaItem>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final data = await _get(
      'search/multi',
      params: {'query': trimmed, 'include_adult': 'false'},
    );
    final results = data['results'];
    if (results is! List) return const [];

    final items = <MediaItem>[];
    for (final entry in results) {
      if (items.length >= _pageLimit) break;
      if (entry is! Map<String, dynamic>) continue;
      final item = MediaItem.fromJson(entry);
      if (item != null && item.posterPath != null) items.add(item);
    }
    return items;
  }

  /// Fills in the fields a stored watchlist entry does not carry.
  static Future<MediaItem> hydrate(MediaItem stored) async {
    try {
      final detail = await Tmdb.detail(stored.id, stored.type);
      return stored.mergedWith(detail.item);
    } on Object {
      // A hydrate failure should never stop a title from opening.
      return stored;
    }
  }

  static String? _firstLogo(Object? images) {
    if (images is! Map<String, dynamic>) return null;
    final logos = images['logos'];
    if (logos is! List) return null;

    for (final logo in logos.whereType<Map<String, dynamic>>()) {
      final path = logo['file_path'];
      // SVG logos cannot be decoded by the image pipeline, so only PNGs are useful.
      if (path is String && path.endsWith('.png')) return path;
    }
    return null;
  }

  static List<CastMember> _cast(Object? credits) {
    if (credits is! Map<String, dynamic>) return const [];
    final cast = credits['cast'];
    if (cast is! List) return const [];

    return cast
        .whereType<Map<String, dynamic>>()
        .take(16)
        .map(CastMember.fromJson)
        .toList(growable: false);
  }

  static List<MediaItem> _recommendations(Object? block, String type) {
    if (block is! Map<String, dynamic>) return const [];
    final results = block['results'];
    if (results is! List) return const [];

    return results
        .whereType<Map<String, dynamic>>()
        .map((json) => MediaItem.fromJson(json, forcedType: type))
        .whereType<MediaItem>()
        .where((item) => item.posterPath != null)
        .take(_pageLimit)
        .toList(growable: false);
  }

  static List<Season> _seasons(Object? seasons) {
    if (seasons is! List) return const [];

    return seasons
        .whereType<Map<String, dynamic>>()
        .map((json) => Season(
              number: (json['season_number'] as num?)?.toInt() ?? 0,
              episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
            ))
        .where((season) => season.number > 0 && season.episodeCount > 0)
        .toList(growable: false);
  }
}

class TmdbException implements Exception {
  const TmdbException(this.message);

  final String message;

  @override
  String toString() => message;
}
