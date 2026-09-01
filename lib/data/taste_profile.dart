import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// The "four films, four series" taste picks and the vector buddy matching runs
/// on. Ported from `stream-sync/lib/tasteProfile.js` — the two clients read and
/// write the same `users/{uid}` document, so the maths has to agree exactly or
/// a profile written on the phone would score differently on the web.
class TasteProfile {
  const TasteProfile({
    this.genres = const {},
    this.keywords = const {},
    this.people = const {},
    this.decades = const {},
    this.titles = const [],
    this.topGenres = const [],
    this.keywordLabels = const {},
    this.peopleLabels = const {},
    this.pickCount = 0,
  });

  final Map<String, double> genres;
  final Map<String, double> keywords;
  final Map<String, double> people;
  final Map<String, double> decades;
  final List<String> titles;
  final List<String> topGenres;
  final Map<String, String> keywordLabels;
  final Map<String, String> peopleLabels;
  final int pickCount;

  static const maxPicksPerType = 4;
  static const totalPickSlots = maxPicksPerType * 2;
  static const version = 1;

  static const _keywordsPerTitle = 8;
  static const _castPerTitle = 3;
  static const _topGenreCount = 6;
  static const _labelCap = 16;
  static const _cap = {'genres': 24, 'keywords': 64, 'people': 40, 'decades': 8};

  bool get isEmpty => pickCount == 0;

  Map<String, dynamic> toMap() => {
        'version': version,
        'genres': genres,
        'keywords': keywords,
        'people': people,
        'decades': decades,
        'labels': {'keywords': keywordLabels, 'people': peopleLabels},
        'titles': titles,
        'topGenres': topGenres,
        'pickCount': pickCount,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static TasteProfile? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final labels = raw['labels'];

    return TasteProfile(
      genres: _numMap(raw['genres']),
      keywords: _numMap(raw['keywords']),
      people: _numMap(raw['people']),
      decades: _numMap(raw['decades']),
      titles: _stringList(raw['titles']),
      topGenres: _stringList(raw['topGenres']),
      keywordLabels: labels is Map ? _stringMap(labels['keywords']) : const {},
      peopleLabels: labels is Map ? _stringMap(labels['people']) : const {},
      pickCount: (raw['pickCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, double> _numMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num) '${entry.key}': (entry.value as num).toDouble(),
    };
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {for (final e in raw.entries) '${e.key}': '${e.value}'};
  }

  static List<String> _stringList(Object? raw) =>
      raw is List ? raw.map((e) => '$e').toList(growable: false) : const [];
}

/// One chosen title. Deliberately small: the picks grid renders straight from
/// this and never re-fetches.
class TastePick {
  const TastePick({
    required this.id,
    required this.type,
    required this.title,
    this.posterPath,
    this.year = '',
  });

  final int id;
  final String type;
  final String title;
  final String? posterPath;
  final String year;

  String get key => '$type:$id';

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'title': title,
        'poster_path': posterPath,
        'year': year,
      };

  static TastePick fromMedia(MediaItem item) => TastePick(
        id: item.id,
        type: item.type,
        title: item.title,
        posterPath: item.posterPath,
        year: item.year,
      );

  static TastePick? fromMap(Object? raw, String type) {
    if (raw is! Map) return null;
    final id = (raw['id'] as num?)?.toInt();
    if (id == null) return null;

    return TastePick(
      id: id,
      type: raw['type'] as String? ?? type,
      title: raw['title'] as String? ?? 'Untitled',
      posterPath: raw['poster_path'] as String?,
      year: raw['year'] as String? ?? '',
    );
  }

  MediaItem toMedia() => MediaItem(
        id: id,
        type: type,
        title: title,
        posterPath: posterPath,
        releaseDate: year.isEmpty ? null : year,
      );
}

class TastePicks {
  const TastePicks({this.movies = const [], this.shows = const []});

  final List<TastePick> movies;
  final List<TastePick> shows;

  int get count => movies.length + shows.length;

  List<TastePick> get all => [...movies, ...shows];

  List<TastePick> forType(String type) => type == 'tv' ? shows : movies;

  TastePicks toggle(TastePick pick) {
    final isTv = pick.type == 'tv';
    final list = [...(isTv ? shows : movies)];
    final existing = list.indexWhere((entry) => entry.id == pick.id);

    if (existing >= 0) {
      list.removeAt(existing);
    } else {
      if (list.length >= TasteProfile.maxPicksPerType) return this;
      list.add(pick);
    }
    return isTv ? TastePicks(movies: movies, shows: list) : TastePicks(movies: list, shows: shows);
  }

  bool contains(int id, String type) =>
      forType(type).any((entry) => entry.id == id);

  static TastePicks fromMap(Object? raw) {
    if (raw is! Map) return const TastePicks();

    List<TastePick> clean(Object? list, String type) => (list is List ? list : const [])
        .map((entry) => TastePick.fromMap(entry, type))
        .whereType<TastePick>()
        .take(TasteProfile.maxPicksPerType)
        .toList(growable: false);

    return TastePicks(
      movies: clean(raw['movies'], 'movie'),
      shows: clean(raw['shows'], 'tv'),
    );
  }

  Map<String, dynamic> toMap() => {
        'movies': movies.map((p) => p.toMap()).toList(),
        'shows': shows.map((p) => p.toMap()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
}

/// TMDB genre ids to names, matching `stream-sync/lib/tmdb.js`.
const kGenreNames = <int, String>{
  28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy', 80: 'Crime',
  99: 'Documentary', 18: 'Drama', 10751: 'Family', 14: 'Fantasy', 36: 'History',
  27: 'Horror', 10402: 'Music', 9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi',
  10770: 'TV Movie', 53: 'Thriller', 10752: 'War', 37: 'Western',
  10759: 'Action & Adventure', 10762: 'Kids', 10763: 'News', 10764: 'Reality',
  10765: 'Sci-Fi & Fantasy', 10766: 'Soap', 10767: 'Talk', 10768: 'War & Politics',
};

String? genreNameFor(Object? id) => kGenreNames[int.tryParse('$id') ?? -1];

/// Builds and persists taste profiles.
class TasteRepo {
  TasteRepo({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String? get uid => _auth.currentUser?.uid;

  Future<TastePicks> myPicks() async {
    final userId = uid;
    if (userId == null) return const TastePicks();
    final snap = await _db.collection('users').doc(userId).get();
    return TastePicks.fromMap(snap.data()?['tastePicks']);
  }

  /// Saves picks and the profile derived from them in one write, exactly as the
  /// website does, so Discover on either client sees the same vectors.
  Future<TasteProfile> savePicks(TastePicks picks, {List<int> fallbackGenreIds = const []}) async {
    final userId = uid;
    if (userId == null) return const TasteProfile();

    final profile = await buildProfile(picks, fallbackGenreIds: fallbackGenreIds);
    await _db.collection('users').doc(userId).set({
      'tastePicks': picks.toMap(),
      'tasteProfile': profile.toMap(),
      'hasTastePicks': profile.pickCount > 0,
    }, SetOptions(merge: true));

    return profile;
  }

  /// One request per pick, thanks to append_to_response.
  static Future<TasteProfile> buildProfile(
    TastePicks picks, {
    List<int> fallbackGenreIds = const [],
  }) async {
    final all = picks.all;
    final facets = await Future.wait(all.map(_fetchFacets));

    final genres = <String, double>{};
    final keywords = <String, double>{};
    final people = <String, double>{};
    final decades = <String, double>{};
    final keywordLabels = <String, String>{};
    final peopleLabels = <String, String>{};

    for (final facet in facets) {
      if (facet == null) continue;

      for (final id in facet.genres) {
        _bump(genres, '$id', 1 / facet.genres.length);
      }
      for (final id in facet.keywords) {
        _bump(keywords, '$id', 1 / facet.keywords.length);
      }
      // Creators count double: a shared favourite director says more than a
      // supporting actor who turns up in everything.
      for (final id in facet.authors) {
        _bump(people, '$id', 2);
      }
      for (final id in facet.cast) {
        _bump(people, '$id', 1);
      }
      if (facet.decade != null) _bump(decades, facet.decade!, 1);

      keywordLabels.addAll(facet.keywordLabels);
      peopleLabels.addAll(facet.peopleLabels);
    }

    // Sparse profiles lean on watch history to cover the empty slots.
    final filled = math.min(all.length, TasteProfile.totalPickSlots);
    final fallbackMass = TasteProfile.totalPickSlots - filled;
    if (fallbackMass > 0 && fallbackGenreIds.isNotEmpty) {
      final share = (fallbackMass * 0.4) / fallbackGenreIds.length;
      for (final id in fallbackGenreIds) {
        _bump(genres, '$id', share);
      }
    }

    final genreVector = _finalize(genres, TasteProfile._cap['genres']!);
    final keywordVector = _finalize(keywords, TasteProfile._cap['keywords']!);
    final peopleVector = _finalize(people, TasteProfile._cap['people']!);

    Map<String, String> keepLabels(Map<String, String> source, Map<String, double> vector) => {
          for (final id in vector.keys.take(TasteProfile._labelCap))
            if (source[id] != null) id: source[id]!,
        };

    return TasteProfile(
      genres: genreVector,
      keywords: keywordVector,
      people: peopleVector,
      decades: _finalize(decades, TasteProfile._cap['decades']!),
      keywordLabels: keepLabels(keywordLabels, keywordVector),
      peopleLabels: keepLabels(peopleLabels, peopleVector),
      titles: all.map((pick) => pick.key).toList(growable: false),
      // Denormalised shard key: Firestore has no vector search, so candidates
      // are shortlisted with array-contains-any before being ranked properly.
      topGenres: genreVector.keys.take(TasteProfile._topGenreCount).toList(growable: false),
      pickCount: all.length,
    );
  }

  static void _bump(Map<String, double> map, String key, double weight) {
    if (weight == 0 || weight.isNaN) return;
    map[key] = (map[key] ?? 0) + weight;
  }

  /// Trims to the heaviest entries and L2-normalises, so cosine similarity
  /// between two stored profiles is a plain dot product later.
  static Map<String, double> _finalize(Map<String, double> map, int cap) {
    final entries = map.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final kept = entries.take(cap).toList();

    final norm = math.sqrt(kept.fold<double>(0, (sum, e) => sum + e.value * e.value));
    if (norm == 0) return const {};

    return {
      for (final entry in kept)
        entry.key: ((entry.value / norm) * 10000).round() / 10000,
    };
  }

  static Future<_Facets?> _fetchFacets(TastePick pick) async {
    final key = dotenv.env['TMDB_API_KEY'] ?? '';
    final uri = Uri.https('api.themoviedb.org', '/3/${pick.type}/${pick.id}', {
      'api_key': key,
      'language': 'en-US',
      'append_to_response': 'keywords,credits',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final keywordBlock = data['keywords'];
      final rawKeywords = keywordBlock is Map
          ? (keywordBlock['keywords'] ?? keywordBlock['results'])
          : null;
      final credits = data['credits'];
      final crew = credits is Map ? credits['crew'] : null;
      final cast = credits is Map ? credits['cast'] : null;

      // Directors for film, creators for series — the strongest authorship signal.
      final authors = pick.type == 'tv'
          ? (data['created_by'] is List ? data['created_by'] as List : const [])
          : (crew is List
              ? crew.where((m) => m is Map && m['job'] == 'Director').toList()
              : const []);

      final topKeywords = (rawKeywords is List ? rawKeywords : const [])
          .whereType<Map>()
          .take(TasteProfile._keywordsPerTitle)
          .toList();
      final topCast = (cast is List ? cast : const [])
          .whereType<Map>()
          .take(TasteProfile._castPerTitle)
          .toList();

      int? idOf(Object? entry) =>
          entry is Map ? (entry['id'] as num?)?.toInt() : null;

      return _Facets(
        genres: (data['genres'] is List ? data['genres'] as List : const [])
            .map(idOf)
            .whereType<int>()
            .toList(),
        keywords: topKeywords.map(idOf).whereType<int>().toList(),
        authors: authors.map(idOf).whereType<int>().toList(),
        cast: topCast.map(idOf).whereType<int>().toList(),
        decade: _decadeOf(data['release_date'] ?? data['first_air_date']),
        // Labels ride along so a match explanation never needs a second lookup.
        keywordLabels: {
          for (final k in topKeywords)
            if (idOf(k) != null) '${idOf(k)}': '${k['name']}',
        },
        peopleLabels: {
          for (final p in [...authors, ...topCast])
            if (idOf(p) != null) '${idOf(p)}': '${(p as Map)['name']}',
        },
      );
    } on Object {
      // One unreachable title should not sink the whole profile.
      return null;
    }
  }

  static String? _decadeOf(Object? date) {
    final year = int.tryParse('$date'.padRight(4).substring(0, 4).trim());
    return year == null ? null : '${(year ~/ 10) * 10}';
  }
}

class _Facets {
  const _Facets({
    required this.genres,
    required this.keywords,
    required this.authors,
    required this.cast,
    required this.decade,
    required this.keywordLabels,
    required this.peopleLabels,
  });

  final List<int> genres;
  final List<int> keywords;
  final List<int> authors;
  final List<int> cast;
  final String? decade;
  final Map<String, String> keywordLabels;
  final Map<String, String> peopleLabels;
}
