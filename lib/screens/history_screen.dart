import 'package:flutter/material.dart';

import '../data/library_repo.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import 'watchlist_screen.dart';

/// What this account has opened, most recent first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final LibraryRepo _library = LibraryRepo();

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.lg)),
        title: const Text('Clear history?', style: AppText.headingSm),
        content: const Text(
          'This removes every title from Continue Watching on all your devices.',
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
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _library.clearHistory();
      if (mounted) showAppSnack(context, 'History cleared', success: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LibraryListFrame(
      eyebrow: 'Your library',
      title: 'History',
      subtitle: 'Pick up where you left off.',
      stream: _library.watchHistory(),
      emptyIcon: Icons.history_rounded,
      emptyTitle: 'Nothing watched yet',
      emptyMessage: 'Play something and it will show up here.',
      trailing: IconButton(
        onPressed: _confirmClear,
        icon: const Icon(Icons.delete_outline_rounded),
        color: AppColors.textSecondary,
        tooltip: 'Clear history',
      ),
    );
  }
}
