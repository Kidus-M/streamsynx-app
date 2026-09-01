import 'package:flutter/material.dart';

import '../data/deep_links.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The three ways a title leaves the app.
enum ShareChoice { link, copy, poster }

/// Asks how to share, with the link first.
///
/// The previous build only ever produced a PNG, which is why a shared title
/// arrived as a flat picture: hand a messaging app a file and it sends a file,
/// dropping the caption on most targets. A bare URL is what unfurls into the
/// card people expect from Letterboxd or Spotify — the `/open` page carries the
/// Open Graph tags that build it — so that is the default now, and the poster is
/// kept for the one place it is genuinely better: a story.
Future<ShareChoice?> showShareSheet(
  BuildContext context, {
  required MediaItem item,
}) {
  final link = DeepLinks.forItem(item);

  return showModalBottomSheet<ShareChoice>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.bgSoft,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpace.md),
              decoration: BoxDecoration(
                color: AppColors.hairlineStrong,
                borderRadius: AppRadius.all(AppRadius.pill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SHARE', style: AppText.eyebrow),
                const SizedBox(height: AppSpace.xs),
                Text(item.title, style: AppText.headingLg, maxLines: 1),
                const SizedBox(height: AppSpace.xs),
                Text(
                  link.replaceFirst(RegExp(r'^https?://'), ''),
                  style: AppText.caption.copyWith(color: AppColors.accentSoft),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _Option(
            icon: Icons.link_rounded,
            title: 'Send the link',
            body: 'Unfurls into a card with the poster, wherever you paste it',
            highlight: true,
            onTap: () => Navigator.of(sheetContext).pop(ShareChoice.link),
          ),
          _Option(
            icon: Icons.copy_rounded,
            title: 'Copy link',
            body: 'Put it on the clipboard',
            onTap: () => Navigator.of(sheetContext).pop(ShareChoice.copy),
          ),
          _Option(
            icon: Icons.auto_awesome_mosaic_rounded,
            title: 'Share as a story',
            body: 'A 9:16 image for Instagram or WhatsApp',
            onTap: () => Navigator.of(sheetContext).pop(ShareChoice.poster),
          ),
          const SizedBox(height: AppSpace.md),
        ],
      ),
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: highlight ? AppColors.accent : AppColors.surfaceHigh,
          borderRadius: AppRadius.all(AppRadius.md),
        ),
        child: Icon(
          icon,
          size: 20,
          color: highlight ? AppColors.bg : AppColors.textPrimary,
        ),
      ),
      title: Text(title, style: AppText.label),
      subtitle: Text(body, style: AppText.caption),
    );
  }
}
