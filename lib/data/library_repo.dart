import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';

/// Watchlist, favourites, history, recommendations and resume points.
///
/// Document shapes match the web app so the two clients stay interchangeable:
///
/// - `watchlists/{uid}`      → `{ items: [...] }`
/// - `favorites/{uid}`       → `{ movies: [...] }`
/// - `history/{uid}`         → `{ items: [...] }`
/// - `recommendations/{uid}` → `{ movies: [...] }`
/// - `progress/{uid}`        → `{ '<type>:<id>[:s:e]': { positionMs, durationMs } }`
class LibraryRepo {
  LibraryRepo({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const _historyLimit = 60;

  String? get uid => _auth.currentUser?.uid;

  // --- Watchlist ---------------------------------------------------------------

  Stream<List<MediaItem>> watchWatchlist() => _watchList('watchlists', 'items');

  Future<bool> isInWatchlist(MediaItem item) async =>
      (await _read('watchlists', 'items')).any((stored) => _same(stored, item));

  /// @return true when the item is in the watchlist after the toggle.
  Future<bool> toggleWatchlist(MediaItem item) =>
      _toggle('watchlists', 'items', item);

  // --- Favourites --------------------------------------------------------------

  /// Favourites are the one collection the web app splits by media type:
  /// `movies` holds films as `{id, title, poster_path}`, and `episodes` holds
  /// series under different key names entirely (`tvShowId`, `tvShowName`).
  /// Writing everything into `movies` would make anything favourited here
  /// invisible on the website, and vice versa.
  static String _favoritesField(MediaItem item) => item.isTv ? 'episodes' : 'movies';

  Stream<List<MediaItem>> watchFavorites() {
    final userId = uid;
    if (userId == null) return Stream.value(const []);

    return _db.collection('favorites').doc(userId).snapshots().map((snap) {
      final data = snap.data();
      return [
        ..._itemsOf(data, 'movies').map(MediaItem.fromStored),
        ..._itemsOf(data, 'episodes').map(MediaItem.fromStored),
      ];
    });
  }

  Future<bool> isFavorite(MediaItem item) async {
    final entries = await _read('favorites', _favoritesField(item));
    return entries.any((stored) => _sameFavorite(stored, item));
  }

  /// @return true when the item is a favourite after the toggle.
  Future<bool> toggleFavorite(MediaItem item) async {
    final userId = uid;
    if (userId == null) return false;

    final field = _favoritesField(item);
    final ref = _db.collection('favorites').doc(userId);
    final snap = await ref.get();
    final entries = _itemsOf(snap.data(), field);
    final wasPresent = entries.any((stored) => _sameFavorite(stored, item));

    if (wasPresent) {
      entries.removeWhere((stored) => _sameFavorite(stored, item));
    } else {
      entries.insert(0, _favoriteEntry(item));
    }

    await ref.set({field: entries}, SetOptions(merge: true));
    return !wasPresent;
  }

  static Map<String, dynamic> _favoriteEntry(MediaItem item) => item.isTv
      ? {
          'tvShowId': item.id,
          'tvShowName': item.title,
          'poster_path': item.posterPath,
          'type': 'tv',
          'favoritedAt': DateTime.now().toIso8601String(),
        }
      : {
          'id': item.id,
          'title': item.title,
          'poster_path': item.posterPath,
        };

  static bool _sameFavorite(Map<String, dynamic> stored, MediaItem item) {
    final id = ((item.isTv ? stored['tvShowId'] : stored['id']) as num?)?.toInt();
    return id == item.id;
  }

  // --- History -----------------------------------------------------------------

  Stream<List<MediaItem>> watchHistory() => _watchList('history', 'items');

  /// Moves an item to the front of history, de-duplicating any earlier entry.
  Future<void> recordWatch(MediaItem item) async {
    final userId = uid;
    if (userId == null) return;

    final ref = _db.collection('history').doc(userId);
    final snap = await ref.get();
    final items = _itemsOf(snap.data(), 'items')
      ..removeWhere((stored) => _same(stored, item));
    items.insert(0, item.toStored());

    await ref.set({
      'items': items.take(_historyLimit).toList(growable: false),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearHistory() async {
    final userId = uid;
    if (userId == null) return;
    await _db.collection('history').doc(userId).set({'items': []}, SetOptions(merge: true));
  }

  // --- Recommendations ---------------------------------------------------------

  Stream<List<Recommendation>> watchRecommendations() {
    final userId = uid;
    if (userId == null) return Stream.value(const []);

    return _db.collection('recommendations').doc(userId).snapshots().map((snap) {
      final movies = snap.data()?['movies'];
      if (movies is! List) return const <Recommendation>[];
      return movies
          .whereType<Map<String, dynamic>>()
          .map(Recommendation.fromStored)
          .toList(growable: false)
          .reversed
          .toList(growable: false);
    });
  }

  Future<void> recommend({
    required MediaItem item,
    required String toUserId,
    required String fromUsername,
  }) async {
    final userId = uid;
    if (userId == null) return;

    await _db.collection('recommendations').doc(toUserId).set({
      'movies': FieldValue.arrayUnion([
        {
          ...item.toStored(),
          'type': item.type,
          'recommendedBy': userId,
          'recommendedByUsername': fromUsername,
          'recommendedAt': DateTime.now().toIso8601String(),
        }
      ]),
    }, SetOptions(merge: true));
  }

  Future<void> dismissRecommendation(Recommendation recommendation) async {
    final userId = uid;
    if (userId == null) return;

    final ref = _db.collection('recommendations').doc(userId);
    final snap = await ref.get();
    final movies = _itemsOf(snap.data(), 'movies')
      ..removeWhere((stored) =>
          (stored['id'] as num?)?.toInt() == recommendation.item.id &&
          stored['recommendedBy'] == recommendation.fromUid);

    await ref.set({'movies': movies}, SetOptions(merge: true));
  }

  // --- Resume points -----------------------------------------------------------

  /// Below this a resume point is noise; past [_resumeEndMs] from the end the
  /// title counts as finished and the point is cleared.
  static const _resumeMinMs = 15000;
  static const _resumeEndMs = 120000;

  Future<void> saveProgress({
    required MediaItem item,
    required int season,
    required int episode,
    required int positionMs,
    required int durationMs,
  }) async {
    final userId = uid;
    if (userId == null) return;

    final ref = _db.collection('progress').doc(userId);
    final key = _progressKey(item, season, episode);

    final finished = durationMs > 0 && positionMs > durationMs - _resumeEndMs;
    if (finished) {
      await ref.set({key: FieldValue.delete()}, SetOptions(merge: true));
      return;
    }
    if (positionMs < _resumeMinMs) return;

    await ref.set({
      key: {'positionMs': positionMs, 'durationMs': durationMs},
    }, SetOptions(merge: true));
  }

  Future<int> progressFor(MediaItem item, int season, int episode) async {
    final userId = uid;
    if (userId == null) return 0;

    final snap = await _db.collection('progress').doc(userId).get();
    final entry = snap.data()?[_progressKey(item, season, episode)];
    if (entry is! Map) return 0;
    return (entry['positionMs'] as num?)?.toInt() ?? 0;
  }

  String _progressKey(MediaItem item, int season, int episode) =>
      item.isTv ? '${item.type}:${item.id}:$season:$episode' : '${item.type}:${item.id}';

  // --- Shared plumbing ---------------------------------------------------------

  Stream<List<MediaItem>> _watchList(String collection, String field) {
    final userId = uid;
    if (userId == null) return Stream.value(const []);

    return _db.collection(collection).doc(userId).snapshots().map((snap) => _itemsOf(
          snap.data(),
          field,
        ).map(MediaItem.fromStored).toList(growable: false));
  }

  Future<List<Map<String, dynamic>>> _read(String collection, String field) async {
    final userId = uid;
    if (userId == null) return const [];
    final snap = await _db.collection(collection).doc(userId).get();
    return _itemsOf(snap.data(), field);
  }

  Future<bool> _toggle(String collection, String field, MediaItem item) async {
    final userId = uid;
    if (userId == null) return false;

    final ref = _db.collection(collection).doc(userId);
    final snap = await ref.get();
    final items = _itemsOf(snap.data(), field);
    final wasPresent = items.any((stored) => _same(stored, item));

    if (wasPresent) {
      items.removeWhere((stored) => _same(stored, item));
    } else {
      items.insert(0, item.toStored());
    }

    await ref.set({field: items}, SetOptions(merge: true));
    return !wasPresent;
  }

  static List<Map<String, dynamic>> _itemsOf(Map<String, dynamic>? data, String field) {
    final value = data?[field];
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).toList();
  }

  /// Stored entries predate the `media_type` field on some documents, so a
  /// missing type is treated as a film rather than dropping the row.
  static bool _same(Map<String, dynamic> stored, MediaItem item) {
    final id = (stored['id'] as num?)?.toInt();
    final type = stored['media_type'] as String? ?? 'movie';
    return id == item.id && type == item.type;
  }
}

class Recommendation {
  const Recommendation({
    required this.item,
    required this.fromUid,
    required this.fromUsername,
    this.at,
  });

  final MediaItem item;
  final String fromUid;
  final String fromUsername;
  final DateTime? at;

  static Recommendation fromStored(Map<String, dynamic> json) => Recommendation(
        item: MediaItem.fromStored({
          ...json,
          'media_type': json['media_type'] ?? json['type'] ?? 'movie',
        }),
        fromUid: json['recommendedBy'] as String? ?? '',
        fromUsername: json['recommendedByUsername'] as String? ?? 'Someone',
        at: DateTime.tryParse(json['recommendedAt'] as String? ?? ''),
      );
}
