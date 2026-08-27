import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/library_repo.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import 'details_screen.dart';

/// Titles buddies have sent this account.
class RecommendedScreen extends StatefulWidget {
  const RecommendedScreen({super.key});

  @override
  State<RecommendedScreen> createState() => _RecommendedScreenState();
}

class _RecommendedScreenState extends State<RecommendedScreen> {
  final LibraryRepo _library = LibraryRepo();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('From your buddies'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: StreamBuilder<List<Recommendation>>(
        stream: _library.watchRecommendations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final recommendations = snapshot.data ?? const <Recommendation>[];
          if (recommendations.isEmpty) {
            return const EmptyState(
              icon: Icons.auto_awesome_rounded,
              title: 'Nothing recommended yet',
              message:
                  'When a buddy sends you a title, it lands here with their name on it.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
            itemCount: recommendations.length,
            itemBuilder: (_, index) => _RecommendationTile(
              recommendation: recommendations[index],
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DetailsScreen(item: recommendations[index].item),
                ),
              ),
              onDismiss: () async {
                await _library.dismissRecommendation(recommendations[index]);
                if (context.mounted) showAppSnack(context, 'Removed');
              },
            ),
          );
        },
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({
    required this.recommendation,
    required this.onOpen,
    required this.onDismiss,
  });

  final Recommendation recommendation;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final item = recommendation.item;

    return Dismissible(
      key: ValueKey('${item.type}-${item.id}-${recommendation.fromUid}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpace.xl),
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.15),
          borderRadius: AppRadius.all(AppRadius.md),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: AppRadius.all(AppRadius.md),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpace.md),
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: AppDecoration.surface(radius: AppRadius.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.all(AppRadius.sm),
                child: SizedBox(
                  width: 64,
                  height: 96,
                  child: item.posterUrl.isEmpty
                      ? const ColoredBox(color: AppColors.surfaceHigh)
                      : CachedNetworkImage(
                          imageUrl: item.posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              const ColoredBox(color: AppColors.surfaceHigh),
                          errorWidget: (_, __, ___) =>
                              const ColoredBox(color: AppColors.surfaceHigh),
                        ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppText.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(item.kindLabel, style: AppText.caption),
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      children: [
                        const Icon(Icons.person_rounded,
                            size: 13, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'from ${recommendation.fromUsername}',
                            style: AppText.caption.copyWith(color: AppColors.accent),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
