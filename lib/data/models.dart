/// Domain models shared by every screen.
///
/// TMDB returns loosely typed JSON with two different shapes for films and
/// series; parsing it once here keeps that difference out of the widgets.
library;

import 'tmdb.dart';

class MediaItem {
  MediaItem({
    required this.id,
    required this.type,
    required this.title,
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.logoPath,
    this.releaseDate,
    this.rating = 0,
    this.runtime = 0,
    this.imdbId,
    this.tagline,
    this.genres = const [],
  });

  final int id;

  /// Either `movie` or `tv`.
  final String type;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String? logoPath;
  final String? releaseDate;
  final double rating;
  final int runtime;
  final String? imdbId;
  final String? tagline;
  final List<String> genres;

  bool get isTv => type == 'tv';

  String get kindLabel => isTv ? 'Series' : 'Film';

  String get year =>
      (releaseDate != null && releaseDate!.length >= 4) ? releaseDate!.substring(0, 4) : '';

  String get posterUrl => Tmdb.image(posterPath, Tmdb.w342) ?? '';

  String get backdropUrl => Tmdb.image(backdropPath, Tmdb.w780) ?? '';

  /// "2024 · Film · Action · Drama" — the caption the web card shows.
  String get caption => _join([year, kindLabel, ...genres.take(2)]);

  String metaLine({int season = 0, int episode = 0}) => _join([
        kindLabel,
        year,
        if (isTv && season > 0) 'S$season E$episode',
        if (!isTv && runtime > 0) '${runtime ~/ 60}h ${runtime % 60}m',
        if (rating > 0) rating.toStringAsFixed(1),
        ...genres.take(2),
      ]);

  static String _join(List<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join('  ·  ');

  static MediaItem? fromJson(Map<String, dynamic> json, {String? forcedType}) {
    final type = forcedType ?? json['media_type'] as String?;
    if (type != 'movie' && type != 'tv') return null;

    final id = json['id'];
    if (id is! int) return null;

    return MediaItem(
      id: id,
      type: type!,
      title: (type == 'movie' ? json['title'] : json['name']) as String? ?? 'Untitled',
      overview: json['overview'] as String? ?? '',
      posterPath: _clean(json['poster_path']),
      backdropPath: _clean(json['backdrop_path']),
      releaseDate:
          (type == 'movie' ? json['release_date'] : json['first_air_date']) as String?,
      rating: _toDouble(json['vote_average']),
      runtime: _runtimeOf(json),
      imdbId: _clean(json['imdb_id']),
      tagline: json['tagline'] as String?,
      genres: _genresOf(json),
    );
  }

  /// Watchlist and history entries are stored as a trimmed shape in Firestore.
  static MediaItem fromStored(Map<String, dynamic> json) => MediaItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['media_type'] as String? ?? 'movie',
        title: json['title'] as String? ?? json['name'] as String? ?? 'Untitled',
        posterPath: _clean(json['poster_path']),
        backdropPath: _clean(json['backdrop_path']),
        releaseDate: json['release_date'] as String?,
        rating: _toDouble(json['vote_average']),
      );

  /// Kept deliberately small: this is what gets written to every user document.
  Map<String, dynamic> toStored() => {
        'id': id,
        'media_type': type,
        'title': title,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'release_date': releaseDate,
        'vote_average': rating,
      };

  MediaItem mergedWith(MediaItem other) => MediaItem(
        id: id,
        type: type,
        title: other.title.isNotEmpty ? other.title : title,
        overview: other.overview.isNotEmpty ? other.overview : overview,
        posterPath: other.posterPath ?? posterPath,
        backdropPath: other.backdropPath ?? backdropPath,
        logoPath: other.logoPath ?? logoPath,
        releaseDate: other.releaseDate ?? releaseDate,
        rating: other.rating > 0 ? other.rating : rating,
        runtime: other.runtime > 0 ? other.runtime : runtime,
        imdbId: other.imdbId ?? imdbId,
        tagline: other.tagline ?? tagline,
        genres: other.genres.isNotEmpty ? other.genres : genres,
      );

  MediaItem copyWithLogo(String? logo) => MediaItem(
        id: id,
        type: type,
        title: title,
        overview: overview,
        posterPath: posterPath,
        backdropPath: backdropPath,
        logoPath: logo,
        releaseDate: releaseDate,
        rating: rating,
        runtime: runtime,
        imdbId: imdbId,
        tagline: tagline,
        genres: genres,
      );

  static int _runtimeOf(Map<String, dynamic> json) {
    final runtime = json['runtime'];
    if (runtime is num) return runtime.toInt();
    final episodeRuntimes = json['episode_run_time'];
    if (episodeRuntimes is List && episodeRuntimes.isNotEmpty) {
      final first = episodeRuntimes.first;
      if (first is num) return first.toInt();
    }
    return 0;
  }

  static List<String> _genresOf(Map<String, dynamic> json) {
    final genres = json['genres'];
    if (genres is! List) return const [];
    return genres
        .whereType<Map<String, dynamic>>()
        .map((g) => g['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  static double _toDouble(Object? value) =>
      value is num ? value.toDouble() : 0;

  /// TMDB serialises absent paths as the string "null", which is worse than empty.
  static String? _clean(Object? value) {
    if (value is! String || value.isEmpty || value == 'null') return null;
    return value;
  }
}

class Season {
  const Season({required this.number, required this.episodeCount});

  final int number;
  final int episodeCount;
}

class Episode {
  const Episode({
    required this.number,
    required this.name,
    this.overview = '',
    this.stillPath,
    this.airDate,
    this.runtime = 0,
    this.rating = 0,
  });

  final int number;
  final String name;
  final String overview;
  final String? stillPath;
  final String? airDate;
  final int runtime;
  final double rating;

  String get meta {
    final parts = <String>[
      if (airDate != null && airDate!.isNotEmpty) airDate!,
      if (runtime > 0) '$runtime min',
    ];
    return parts.isEmpty ? 'Episode $number' : parts.join('  ·  ');
  }

  bool get hasAired {
    if (airDate == null || airDate!.length != 10) return true;
    final parsed = DateTime.tryParse(airDate!);
    return parsed == null || !parsed.isAfter(DateTime.now());
  }

  static Episode fromJson(Map<String, dynamic> json) {
    final number = (json['episode_number'] as num?)?.toInt() ?? 0;
    return Episode(
      number: number,
      name: json['name'] as String? ?? 'Episode $number',
      overview: json['overview'] as String? ?? '',
      stillPath: MediaItem._clean(json['still_path']),
      airDate: json['air_date'] as String?,
      runtime: (json['runtime'] as num?)?.toInt() ?? 0,
      rating: MediaItem._toDouble(json['vote_average']),
    );
  }
}

class CastMember {
  const CastMember({required this.name, required this.character, this.profilePath});

  final String name;
  final String character;
  final String? profilePath;

  static CastMember fromJson(Map<String, dynamic> json) => CastMember(
        name: json['name'] as String? ?? '',
        character: json['character'] as String? ?? '',
        profilePath: MediaItem._clean(json['profile_path']),
      );
}

/// Everything a detail screen needs, fetched in one request.
class MediaDetail {
  const MediaDetail({
    required this.item,
    this.cast = const [],
    this.recommendations = const [],
    this.seasons = const [],
  });

  final MediaItem item;
  final List<CastMember> cast;
  final List<MediaItem> recommendations;
  final List<Season> seasons;
}
