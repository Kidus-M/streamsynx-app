import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Friends, requests and user search.
///
/// The schema here is the web app's (`stream-sync/pages/buddies/index.jsx`) and
/// deviating from it is what broke the previous build: it *read* the friend list
/// from `friends/{uid}.friends` but *wrote* accepted friends to
/// `users/{uid}.friendUids`. Nothing ever read that field, so accepting a request
/// appeared to do nothing and the friend never showed up on either device.
///
/// One document shape, used by every client:
///
/// - `friends/{uid}`        → `{ friends: [uid, ...] }`
/// - `friendRequests/{fromUid}_{toUid}` → `{ fromUserId, toUserId, status, createdAt }`
/// - `users/{uid}`          → `{ username, avatar, ... }`
class BuddiesRepo {
  BuddiesRepo({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String? get uid => _auth.currentUser?.uid;

  // --- Reads -------------------------------------------------------------------

  /// Emits the current user's friends, resolved to their profile documents.
  Stream<List<BuddyProfile>> watchFriends() {
    final userId = uid;
    if (userId == null) return Stream.value(const []);

    return _db.collection('friends').doc(userId).snapshots().asyncMap((snap) async {
      if (!snap.exists) return const <BuddyProfile>[];
      final ids = List<String>.from(snap.data()?['friends'] as List? ?? const []);
      return _profilesFor(ids);
    });
  }

  /// Emits incoming pending requests, each carrying the sender's profile.
  Stream<List<FriendRequest>> watchIncomingRequests() {
    final userId = uid;
    if (userId == null) return Stream.value(const []);

    return _db
        .collection('friendRequests')
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snap) async {
      final senderIds = snap.docs
          .map((doc) => doc.data()['fromUserId'] as String?)
          .whereType<String>()
          .toList();
      final profiles = await _profilesFor(senderIds);
      final byId = {for (final profile in profiles) profile.uid: profile};

      return snap.docs
          .map((doc) {
            final fromUserId = doc.data()['fromUserId'] as String?;
            final profile = byId[fromUserId];
            if (profile == null) return null;
            return FriendRequest(requestId: doc.id, from: profile);
          })
          .whereType<FriendRequest>()
          .toList(growable: false);
    });
  }

  /// Emits the set of users this account has an outstanding request to.
  ///
  /// The previous build read this once at startup, so the button state went stale
  /// the moment a request was accepted or withdrawn on another device.
  Stream<Set<String>> watchOutgoingRequests() {
    final userId = uid;
    if (userId == null) return Stream.value(const {});

    return _db
        .collection('friendRequests')
        .where('fromUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => doc.data()['toUserId'] as String?)
            .whereType<String>()
            .toSet());
  }

  Future<List<BuddyProfile>> _profilesFor(List<String> ids) async {
    if (ids.isEmpty) return const [];

    final docs = await Future.wait(
      ids.map((id) => _db.collection('users').doc(id).get()),
    );
    return docs
        .where((doc) => doc.exists)
        .map((doc) => BuddyProfile.fromDoc(doc.id, doc.data() ?? const {}))
        .toList(growable: false);
  }

  /// Username search.
  ///
  /// Firestore has no case-insensitive prefix operator, so this mirrors the web
  /// app: pull a bounded page of users and filter on the client. It is honest
  /// about its ceiling rather than pretending to be a real index.
  Future<List<BuddyProfile>> searchUsers(String query) async {
    final userId = uid;
    final trimmed = query.trim().toLowerCase();
    if (userId == null || trimmed.isEmpty) return const [];

    final snap = await _db.collection('users').limit(100).get();
    return snap.docs
        .where((doc) {
          if (doc.id == userId) return false;
          final username = (doc.data()['username'] as String? ?? '').toLowerCase();
          return username.startsWith(trimmed);
        })
        .map((doc) => BuddyProfile.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  // --- Writes ------------------------------------------------------------------

  Future<void> sendRequest(String toUserId) async {
    final userId = uid;
    if (userId == null || toUserId == userId) return;

    await _db.collection('friendRequests').doc('${userId}_$toUserId').set({
      'fromUserId': userId,
      'toUserId': toUserId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelRequest(String toUserId) async {
    final userId = uid;
    if (userId == null) return;
    await _db.collection('friendRequests').doc('${userId}_$toUserId').delete();
  }

  /// Accepts a request and links both accounts.
  ///
  /// The two friend documents and the request update go through one batch: a
  /// half-applied friendship, where one side sees the other but not the reverse,
  /// is the kind of state that is very hard to recover from by hand.
  Future<void> acceptRequest(String fromUserId) async {
    final userId = uid;
    if (userId == null) return;

    final batch = _db.batch();
    batch.update(
      _db.collection('friendRequests').doc('${fromUserId}_$userId'),
      {'status': 'accepted'},
    );
    batch.set(
      _db.collection('friends').doc(userId),
      {'friends': FieldValue.arrayUnion([fromUserId])},
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection('friends').doc(fromUserId),
      {'friends': FieldValue.arrayUnion([userId])},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> rejectRequest(String fromUserId) async {
    final userId = uid;
    if (userId == null) return;
    // Deleted rather than marked rejected, so the sender's button returns to
    // "Add" instead of sitting on a pending state that can never resolve.
    await _db.collection('friendRequests').doc('${fromUserId}_$userId').delete();
  }

  Future<void> unfriend(String friendId) async {
    final userId = uid;
    if (userId == null) return;

    final batch = _db.batch();
    batch.set(
      _db.collection('friends').doc(userId),
      {'friends': FieldValue.arrayRemove([friendId])},
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection('friends').doc(friendId),
      {'friends': FieldValue.arrayRemove([userId])},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// The signed-in user's own display name, for attributing recommendations.
  Future<String> currentUsername() async {
    final userId = uid;
    if (userId == null) return 'Someone';

    final doc = await _db.collection('users').doc(userId).get();
    final username = doc.data()?['username'] as String?;
    if (username != null && username.isNotEmpty) return username;
    return _auth.currentUser?.displayName ?? 'Someone';
  }
}

class BuddyProfile {
  const BuddyProfile({required this.uid, required this.username, this.avatar});

  final String uid;
  final String username;
  final String? avatar;

  static const fallbackAvatar =
      'https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&f=y';

  String get avatarUrl => (avatar == null || avatar!.isEmpty) ? fallbackAvatar : avatar!;

  String get initial => username.isEmpty ? '?' : username[0].toUpperCase();

  static BuddyProfile fromDoc(String id, Map<String, dynamic> data) => BuddyProfile(
        uid: id,
        username: data['username'] as String? ?? 'Unknown user',
        avatar: data['avatar'] as String?,
      );
}

class FriendRequest {
  const FriendRequest({required this.requestId, required this.from});

  final String requestId;
  final BuddyProfile from;
}
