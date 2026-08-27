import 'dart:async';

import 'package:flutter/material.dart';

import '../data/buddies_repo.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';

/// Friends, incoming requests, and finding people.
///
/// Every list here is a live stream from [BuddiesRepo]; the previous build mixed
/// live listeners with one-shot reads and never cancelled either, so the tabs
/// drifted out of sync and the screen kept calling setState after it was gone.
class BuddiesScreen extends StatefulWidget {
  const BuddiesScreen({super.key});

  @override
  State<BuddiesScreen> createState() => _BuddiesScreenState();
}

class _BuddiesScreenState extends State<BuddiesScreen>
    with SingleTickerProviderStateMixin {
  final BuddiesRepo _repo = BuddiesRepo();
  final TextEditingController _search = TextEditingController();

  late final TabController _tabs = TabController(length: 3, vsync: this);

  Timer? _debounce;
  List<BuddyProfile> _results = const [];
  bool _searching = false;
  final Set<String> _busy = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Debounced so typing a username does not fire a read per keystroke.
  void _onQueryChanged(String value) {
    _debounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 320), () async {
      final results = await _repo.searchUsers(value);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  /// Wraps a write so the row shows a spinner and errors surface instead of
  /// silently doing nothing.
  Future<void> _run(String uid, Future<void> Function() action, String done) async {
    if (_busy.contains(uid)) return;
    setState(() => _busy.add(uid));

    try {
      await action();
      if (mounted) showAppSnack(context, done, success: true);
    } on Object catch (error) {
      if (mounted) showAppSnack(context, 'That did not work. $error');
    } finally {
      if (mounted) setState(() => _busy.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const PageHeader(
              eyebrow: 'Together',
              title: 'Buddies',
              subtitle: 'Share what you are watching with people you know.',
            ),
            _RequestBadgeTabs(repo: _repo, controller: _tabs),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _friendsTab(),
                  _requestsTab(),
                  _addTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendsTab() {
    return StreamBuilder<List<BuddyProfile>>(
      stream: _repo.watchFriends(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final friends = snapshot.data ?? const <BuddyProfile>[];
        if (friends.isEmpty) {
          return EmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No buddies yet',
            message: 'Find people by username and send them a request.',
            actionLabel: 'Find people',
            onAction: () => _tabs.animateTo(2),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
          itemCount: friends.length,
          itemBuilder: (_, index) {
            final friend = friends[index];
            return _BuddyTile(
              profile: friend,
              busy: _busy.contains(friend.uid),
              trailing: _TileAction(
                icon: Icons.person_remove_outlined,
                tone: AppColors.danger,
                tooltip: 'Remove buddy',
                onTap: () => _confirmUnfriend(friend),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmUnfriend(BuddyProfile friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.lg)),
        title: Text('Remove ${friend.username}?', style: AppText.headingSm),
        content: const Text(
          'You will both stop seeing each other in Buddies.',
          style: AppText.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _run(friend.uid, () => _repo.unfriend(friend.uid), 'Removed ${friend.username}');
    }
  }

  Widget _requestsTab() {
    return StreamBuilder<List<FriendRequest>>(
      stream: _repo.watchIncomingRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data ?? const <FriendRequest>[];
        if (requests.isEmpty) {
          return const EmptyState(
            icon: Icons.mark_email_unread_outlined,
            title: 'No requests',
            message: 'When someone asks to be your buddy, it will show up here.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
          itemCount: requests.length,
          itemBuilder: (_, index) {
            final request = requests[index];
            final profile = request.from;

            return _BuddyTile(
              profile: profile,
              busy: _busy.contains(profile.uid),
              subtitle: 'Wants to be your buddy',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TileAction(
                    icon: Icons.check_rounded,
                    tone: AppColors.success,
                    tooltip: 'Accept',
                    onTap: () => _run(
                      profile.uid,
                      () => _repo.acceptRequest(profile.uid),
                      'You and ${profile.username} are now buddies',
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  _TileAction(
                    icon: Icons.close_rounded,
                    tone: AppColors.textSecondary,
                    tooltip: 'Decline',
                    onTap: () => _run(
                      profile.uid,
                      () => _repo.rejectRequest(profile.uid),
                      'Request declined',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _addTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.md),
          child: TextField(
            controller: _search,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'Search by username',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _search.clear();
                        _onQueryChanged('');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<Set<String>>(
            stream: _repo.watchOutgoingRequests(),
            builder: (context, sentSnapshot) {
              final sent = sentSnapshot.data ?? const <String>{};

              if (_searching) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_search.text.trim().isEmpty) {
                return const EmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'Find your people',
                  message: 'Type a username to search. Matching is by the start of the name.',
                );
              }
              if (_results.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  message: 'Nobody with a username starting "${_search.text.trim()}".',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xxl),
                itemCount: _results.length,
                itemBuilder: (_, index) {
                  final profile = _results[index];
                  final pending = sent.contains(profile.uid);

                  return _BuddyTile(
                    profile: profile,
                    busy: _busy.contains(profile.uid),
                    trailing: pending
                        ? _TileAction(
                            icon: Icons.hourglass_bottom_rounded,
                            tone: AppColors.textSecondary,
                            tooltip: 'Cancel request',
                            onTap: () => _run(
                              profile.uid,
                              () => _repo.cancelRequest(profile.uid),
                              'Request withdrawn',
                            ),
                          )
                        : _TileAction(
                            icon: Icons.person_add_alt_1_rounded,
                            tone: AppColors.accent,
                            tooltip: 'Send request',
                            onTap: () => _run(
                              profile.uid,
                              () => _repo.sendRequest(profile.uid),
                              'Request sent to ${profile.username}',
                            ),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The tab bar, with a live count on the Requests tab.
class _RequestBadgeTabs extends StatelessWidget {
  const _RequestBadgeTabs({required this.repo, required this.controller});

  final BuddiesRepo repo;
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FriendRequest>>(
      stream: repo.watchIncomingRequests(),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;

        return TabBar(
          controller: controller,
          tabs: [
            const Tab(text: 'Buddies'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Requests'),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: AppRadius.all(AppRadius.pill),
                      ),
                      child: Text(
                        '$count',
                        style: AppText.caption.copyWith(
                          color: AppColors.bg,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Add'),
          ],
        );
      },
    );
  }
}

class _BuddyTile extends StatelessWidget {
  const _BuddyTile({
    required this.profile,
    required this.trailing,
    this.subtitle,
    this.busy = false,
  });

  final BuddyProfile profile;
  final Widget trailing;
  final String? subtitle;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: AppDecoration.surface(radius: AppRadius.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.surfaceHigh,
            backgroundImage: NetworkImage(profile.avatarUrl),
            onBackgroundImageError: (_, __) {},
            child: Text(
              profile.initial,
              style: AppText.label.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.username,
                  style: AppText.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(subtitle!, style: AppText.caption, maxLines: 1),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            trailing,
        ],
      ),
    );
  }
}

class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.icon,
    required this.tone,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tone.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 19, color: tone),
          ),
        ),
      ),
    );
  }
}
