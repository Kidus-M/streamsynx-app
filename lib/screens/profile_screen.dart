import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/buddies_repo.dart';
import '../data/deep_links.dart';
import '../data/library_repo.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import 'recommended_screen.dart';

/// Account, activity at a glance, and the handful of settings worth having.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final LibraryRepo _library = LibraryRepo();
  final BuddiesRepo _buddies = BuddiesRepo();

  String _username = '';

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final username = await _buddies.currentUsername();
    if (mounted) setState(() => _username = username);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.lg)),
        title: const Text('Sign out?', style: AppText.headingSm),
        content: const Text(
          'Your watchlist and buddies stay on your account.',
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
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed == true) await FirebaseAuth.instance.signOut();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      showAppSnack(context, 'Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpace.xxl),
          children: [
            const PageHeader(eyebrow: 'Account', title: 'Profile'),
            _IdentityCard(
              username: _username.isEmpty ? (user?.displayName ?? 'You') : _username,
              email: user?.email ?? '',
              photoUrl: user?.photoURL,
            ),
            const SizedBox(height: AppSpace.xl),
            _StatsRow(library: _library, buddies: _buddies),
            const SizedBox(height: AppSpace.xl),
            _SettingsGroup(
              title: 'Activity',
              tiles: [
                _SettingsTile(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Recommended by buddies',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecommendedScreen()),
                  ),
                ),
              ],
            ),
            _SettingsGroup(
              title: 'StreamSynx',
              tiles: [
                _SettingsTile(
                  icon: Icons.tv_rounded,
                  label: 'Get the TV app',
                  subtitle: 'Android TV, with the same account',
                  onTap: () => _open(DeepLinks.download),
                ),
                _SettingsTile(
                  icon: Icons.public_rounded,
                  label: 'Open the website',
                  onTap: () => _open(DeepLinks.site),
                ),
              ],
            ),
            _SettingsGroup(
              title: 'Account',
              tiles: [
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  tone: AppColors.danger,
                  onTap: _signOut,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            const Center(
              child: Text('StreamSynx 2.0.0', style: AppText.caption),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.username,
    required this.email,
    required this.photoUrl,
  });

  final String username;
  final String email;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: AppDecoration.surface(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.accentAt(0.16),
            backgroundImage:
                (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
            child: (photoUrl == null || photoUrl!.isEmpty)
                ? Text(
                    username.isEmpty ? '?' : username[0].toUpperCase(),
                    style: AppText.headingLg.copyWith(color: AppColors.accent),
                  )
                : null,
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username, style: AppText.headingSm, maxLines: 1),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.library, required this.buddies});

  final LibraryRepo library;
  final BuddiesRepo buddies;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              label: 'Watchlist',
              stream: library.watchWatchlist().map((items) => items.length),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: _StatTile(
              label: 'Watched',
              stream: library.watchHistory().map((items) => items.length),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: _StatTile(
              label: 'Buddies',
              stream: buddies.watchFriends().map((items) => items.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.stream});

  final String label;
  final Stream<int> stream;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      decoration: AppDecoration.surface(radius: AppRadius.md),
      child: Column(
        children: [
          StreamBuilder<int>(
            stream: stream,
            builder: (context, snapshot) => Text(
              '${snapshot.data ?? 0}',
              style: AppText.display.copyWith(fontSize: 26, color: AppColors.accent),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Eyebrow(label),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(title),
          const SizedBox(height: AppSpace.md),
          Container(
            decoration: AppDecoration.surface(radius: AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: Column(children: tiles),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? AppColors.textPrimary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: AppSpace.lg),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tone ?? AppColors.accent),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.label.copyWith(color: color)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppText.caption),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
