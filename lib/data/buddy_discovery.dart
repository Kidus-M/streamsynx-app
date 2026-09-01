import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'buddies_repo.dart';
import 'taste_match.dart';
import 'taste_profile.dart';

/// A ranked suggestion: who they are, how well they match, and why.
class BuddyMatch {
  const BuddyMatch({required this.profile, required this.match, required this.picks});

  final BuddyProfile profile;
  final TasteMatch match;
  final TastePicks picks;
}

class DiscoveryResult {
  const DiscoveryResult({
    this.matches = const [],
    this.needsPicks = false,
    this.poolSize = 0,
  });

  final List<BuddyMatch> matches;

  /// True when the signed-in user has not chosen any picks yet, so there is
  /// nothing to match against.
  final bool needsPicks;
  final int poolSize;
}

/// Turns "who should I watch with?" into Firestore queries plus a ranking pass.
///
/// Ported from `stream-sync/lib/buddyDiscovery.js`. Firestore cannot rank by
/// similarity, so this is the classic two-stage shape: cheaply shortlist
/// plausible people with an indexed query, then score the shortlist properly in
/// memory.
class BuddyDiscovery {
  BuddyDiscovery({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Ceiling on how many users get scored in one run.
  static const _poolLimit = 150;

  /// How many top matches earn the extra mutual-buddy lookup.
  static const _socialShortlist = 24;

  /// Firestore allows at most 30 values in an array-contains-any clause; the
  /// website uses 10 and this has to shortlist the same people.
  static const _maxContainsAny = 10;

  String? get uid => _auth.currentUser?.uid;

  Future<DiscoveryResult> discover({int limit = 30}) async {
    final userId = uid;
    if (userId == null) return const DiscoveryResult(needsPicks: true);

    final meSnap = await _db.collection('users').doc(userId).get();
    final mine = TasteProfile.fromMap(meSnap.data()?['tasteProfile']);
    if (mine == null || mine.isEmpty) {
      return const DiscoveryResult(needsPicks: true);
    }

    final excluded = await _excludedIds(userId);
    final pool = await _fetchPool(mine.topGenres, userId);
    final candidates = pool.where((c) => !excluded.contains(c.uid)).toList();

    if (candidates.isEmpty) {
      return DiscoveryResult(poolSize: pool.length);
    }

    // Rarity is a property of the pool, so it is measured once and reused by
    // both passes; re-deriving it from the shortlist would shift every score.
    final idf = TasteScorer.buildIdf([mine, ...candidates.map((c) => c.profile)]);

    final firstPass = _rank(mine, candidates, idf: idf, limit: _socialShortlist);
    if (firstPass.isEmpty) return DiscoveryResult(poolSize: pool.length);

    final myFriends = await _friendIds(userId);
    final mutual = await _mutualCounts(
      firstPass.map((entry) => entry.candidate.uid).toList(),
      myFriends,
    );

    final ranked = _rank(
      mine,
      firstPass.map((entry) => entry.candidate).toList(),
      idf: idf,
      limit: limit,
      mutualCounts: mutual,
    );

    return DiscoveryResult(
      matches: ranked
          .map((entry) => BuddyMatch(
                profile: entry.candidate.buddy,
                match: entry.match,
                picks: entry.candidate.picks,
              ))
          .toList(growable: false),
      poolSize: pool.length,
    );
  }

  List<({_Candidate candidate, TasteMatch match})> _rank(
    TasteProfile mine,
    List<_Candidate> candidates, {
    required IdfTables idf,
    required int limit,
    Map<String, int> mutualCounts = const {},
  }) {
    final scored = candidates
        .map((candidate) => (
              candidate: candidate,
              match: TasteScorer.score(
                mine,
                candidate.profile,
                idf: idf,
                mutualCount: mutualCounts[candidate.uid] ?? 0,
              ),
            ))
        .where((entry) => entry.match.score >= TasteScorer.minScore)
        .toList()
      ..sort((a, b) => b.match.score.compareTo(a.match.score));

    return scored.take(limit).toList(growable: false);
  }

  /// Stage one. People whose top genres overlap mine are the only ones with a
  /// realistic shot at a good score, so shard on that first; a second query
  /// then tops the pool up so newcomers and unusual taste are not invisible.
  Future<List<_Candidate>> _fetchPool(List<String> topGenres, String userId) async {
    final found = <String, _Candidate>{};

    Future<void> run(Query<Map<String, dynamic>> query) async {
      try {
        final snap = await query.get();
        for (final doc in snap.docs) {
          if (doc.id == userId || found.containsKey(doc.id)) continue;
          final candidate = _Candidate.fromDoc(doc.id, doc.data());
          if (candidate != null) found[doc.id] = candidate;
        }
      } on Object {
        // A missing composite index should cost one query, not the whole tab.
      }
    }

    if (topGenres.isNotEmpty) {
      await run(_db
          .collection('users')
          .where('tasteProfile.topGenres',
              arrayContainsAny: topGenres.take(_maxContainsAny).toList())
          .limit(_poolLimit));
    }

    if (found.length < _poolLimit) {
      await run(_db
          .collection('users')
          .where('hasTastePicks', isEqualTo: true)
          .limit(_poolLimit - found.length));
    }

    return found.values.toList(growable: false);
  }

  /// Existing buddies and anyone with a request already in flight — suggesting
  /// them again would be noise.
  Future<Set<String>> _excludedIds(String userId) async {
    final excluded = <String>{userId, ...await _friendIds(userId)};

    try {
      final sent = await _db
          .collection('friendRequests')
          .where('fromUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .get();
      for (final doc in sent.docs) {
        final to = doc.data()['toUserId'];
        if (to is String) excluded.add(to);
      }
    } on Object {
      // Worst case a pending request shows up as a suggestion.
    }
    return excluded;
  }

  Future<Set<String>> _friendIds(String userId) async {
    try {
      final snap = await _db.collection('friends').doc(userId).get();
      return List<String>.from(snap.data()?['friends'] as List? ?? const []).toSet();
    } on Object {
      return {};
    }
  }

  /// Mutual buddy counts for a shortlist. Reads are bounded and each failure is
  /// absorbed — a locked-down friends document should cost a social nudge, not
  /// the whole tab.
  Future<Map<String, int>> _mutualCounts(List<String> uids, Set<String> mine) async {
    if (mine.isEmpty) return const {};

    final entries = await Future.wait(uids.map((uid) async {
      try {
        final snap = await _db.collection('friends').doc(uid).get();
        final theirs = List<String>.from(snap.data()?['friends'] as List? ?? const []);
        return MapEntry(uid, theirs.where(mine.contains).length);
      } on Object {
        return MapEntry(uid, 0);
      }
    }));

    return Map.fromEntries(entries);
  }
}

class _Candidate {
  const _Candidate({
    required this.uid,
    required this.buddy,
    required this.profile,
    required this.picks,
  });

  final String uid;
  final BuddyProfile buddy;
  final TasteProfile profile;
  final TastePicks picks;

  static _Candidate? fromDoc(String id, Map<String, dynamic> data) {
    final profile = TasteProfile.fromMap(data['tasteProfile']);
    if (profile == null || profile.isEmpty) return null;

    return _Candidate(
      uid: id,
      buddy: BuddyProfile.fromDoc(id, data),
      profile: profile,
      picks: TastePicks.fromMap(data['tastePicks']),
    );
  }
}
