import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BuddiesScreen extends StatefulWidget {
  const BuddiesScreen({Key? key}) : super(key: key);

  @override
  State<BuddiesScreen> createState() => _BuddiesScreenState();
}

class _BuddiesScreenState extends State<BuddiesScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late TabController _tabController;
  User? get user => _auth.currentUser;

  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> searchResults = [];
  Map<String, bool> sentRequests = {};
  Map<String, bool> loading = {};
  String searchQuery = '';

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _listenToData();
  }

  void _listenToData() {
    if (user == null) return;
    final uid = user!.uid;

    // --- Listen to friends document (just like in web version) ---
    final friendsRef = _db.collection('friends').doc(uid);
    friendsRef.snapshots().listen((docSnap) async {
      if (docSnap.exists) {
        final friendIds = List<String>.from(docSnap.data()?['friends'] ?? []);
        final friendDocs = await Future.wait(friendIds.map((id) async {
          final doc = await _db.collection('users').doc(id).get();
          return doc.exists ? {'uid': id, ...doc.data()!} : null;
        }));
        setState(() {
          friends = friendDocs.whereType<Map<String, dynamic>>().toList();
        });
      } else {
        setState(() => friends = []);
      }
    });

    // --- Listen to incoming friend requests ---
    _db
        .collection('friendRequests')
        .where('toUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) async {
      final reqs = await Future.wait(snapshot.docs.map((d) async {
        final data = d.data();
        final sender = await _db.collection('users').doc(data['fromUserId']).get();
        return sender.exists
            ? {'id': d.id, ...sender.data()!, ...data}
            : null;
      }));
      setState(() {
        requests = reqs.whereType<Map<String, dynamic>>().toList();
      });
    });

    // --- Fetch outgoing friend requests (once) ---
    _db
        .collection('friendRequests')
        .where('fromUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .get()
        .then((snap) {
      final map = <String, bool>{
        for (var doc in snap.docs)
          (doc.data()['toUserId'] as String): true,
      };
      setState(() => sentRequests = map);
    });
  }


  Future<void> _sendRequest(String toUserId) async {
    if (user == null) return;
    final uid = user!.uid;
    final reqId = '${uid}_$toUserId';
    setState(() => loading[toUserId] = true);
    await _db.collection('friendRequests').doc(reqId).set({
      'fromUserId': uid,
      'toUserId': toUserId,
      'status': 'pending',
      'createdAt': DateTime.now(),
    });
    setState(() {
      sentRequests[toUserId] = true;
      loading[toUserId] = false;
    });
  }

  Future<void> _cancelRequest(String toUserId) async {
    if (user == null) return;
    final uid = user!.uid;
    final reqId = '${uid}_$toUserId';
    setState(() => loading[toUserId] = true);
    await _db.collection('friendRequests').doc(reqId).delete();
    setState(() {
      sentRequests.remove(toUserId);
      loading[toUserId] = false;
    });
  }

  Future<void> _acceptRequest(String fromUserId) async {
    if (user == null) return;
    final uid = user!.uid;
    final reqId = '${fromUserId}_$uid';
    await _db.collection('friendRequests').doc(reqId).update({'status': 'accepted'});
    await _db.collection('users').doc(uid).update({
      'friendUids': FieldValue.arrayUnion([fromUserId])
    });
    await _db.collection('users').doc(fromUserId).update({
      'friendUids': FieldValue.arrayUnion([uid])
    });
  }

  Future<void> _rejectRequest(String fromUserId) async {
    if (user == null) return;
    final uid = user!.uid;
    final reqId = '${fromUserId}_$uid';
    await _db.collection('friendRequests').doc(reqId).update({'status': 'rejected'});
  }

  Future<void> _unfriend(String friendId) async {
    if (user == null) return;
    final uid = user!.uid;
    await _db.collection('users').doc(uid).update({
      'friendUids': FieldValue.arrayRemove([friendId])
    });
    await _db.collection('users').doc(friendId).update({
      'friendUids': FieldValue.arrayRemove([uid])
    });
  }

  Future<void> _searchUsers(String query) async {
    final allUsers = await _db.collection('users').limit(100).get();
    final lower = query.toLowerCase();
    final res = allUsers.docs
        .where((u) {
      final username = (u['username'] ?? '').toString().toLowerCase();
      return username.startsWith(lower) && u.id != user?.uid;
    })
        .map((u) => {'uid': u.id, ...u.data()})
        .toList();
    setState(() => searchResults = res);
  }

  Widget _buildUserTile({
    required Map<String, dynamic> userData,
    required String type,
  }) {
    final uid = userData['uid'];
    final isBusy = loading[uid] ?? false;
    final avatar = userData['avatar'] ??
        "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&f=y";

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundImage: NetworkImage(avatar), radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              userData['username'] ?? 'Unknown User',
              style: const TextStyle(color: Color(0xFFEAEAEA), fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (type == 'friend')
            IconButton(
              icon: const Icon(Icons.person_remove, color: Colors.redAccent),
              onPressed: () => _unfriend(uid),
            ),
          if (type == 'request') ...[
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => _acceptRequest(userData['fromUserId']),
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
              onPressed: () => _rejectRequest(userData['fromUserId']),
            ),
          ],
          if (type == 'search')
            isBusy
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : sentRequests[uid] == true
                ? IconButton(
              icon: const Icon(Icons.hourglass_empty,
                  color: Colors.grey),
              onPressed: () => _cancelRequest(uid),
            )
                : IconButton(
              icon:
              const Icon(Icons.person_add, color: Colors.amber),
              onPressed: () => _sendRequest(uid),
            ),
        ],
      ),
    );
  }

  Widget _buildFriendsTab() {
    if (friends.isEmpty) {
      return const Center(
        child: Text(
          "You haven’t added any friends yet.",
          style: TextStyle(color: Color(0xFFA0A0A0)),
        ),
      );
    }
    return ListView.builder(
      itemCount: friends.length,
      itemBuilder: (_, i) =>
          _buildUserTile(userData: friends[i], type: 'friend'),
    );
  }

  Widget _buildRequestsTab() {
    if (requests.isEmpty) {
      return const Center(
        child: Text("No pending friend requests.",
            style: TextStyle(color: Color(0xFFA0A0A0))),
      );
    }
    return ListView.builder(
      itemCount: requests.length,
      itemBuilder: (_, i) =>
          _buildUserTile(userData: requests[i], type: 'request'),
    );
  }

  Widget _buildAddFriendsTab() {
    return Column(
      children: [
        TextField(
          style: const TextStyle(color: Color(0xFFEAEAEA)),
          decoration: InputDecoration(
            hintText: 'Search by username...',
            hintStyle: const TextStyle(color: Color(0xFFA0A0A0)),
            filled: true,
            fillColor: const Color(0xFF121212),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF333333)),
            ),
          ),
          onChanged: (value) {
            setState(() => searchQuery = value);
            if (value.trim().isNotEmpty) _searchUsers(value.trim());
            else setState(() => searchResults = []);
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: searchResults.isEmpty
              ? const Center(
            child: Text("Enter a username to find users.",
                style: TextStyle(color: Color(0xFFA0A0A0))),
          )
              : ListView.builder(
            itemCount: searchResults.length,
            itemBuilder: (_, i) =>
                _buildUserTile(userData: searchResults[i], type: 'search'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Buddies',
            style: TextStyle(color: Color(0xFFEAEAEA), fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFDAA520),
          labelColor: const Color(0xFFDAA520),
          unselectedLabelColor: const Color(0xFFA0A0A0),
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Requests'),
            Tab(text: 'Add Friends'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(),
          _buildRequestsTab(),
          _buildAddFriendsTab(),
        ],
      ),
    );
  }
}
