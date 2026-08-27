import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Small shared pieces so every screen speaks the same visual language.

/// The tracked uppercase eyebrow that sits above a heading, from `.section-label`.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppText.eyebrow.copyWith(color: color),
      );
}

/// A page header: eyebrow, title, optional supporting line.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Eyebrow(eyebrow!, color: AppColors.accent),
                  const SizedBox(height: AppSpace.sm),
                ],
                Text(title, style: AppText.display),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(subtitle!, style: AppText.bodyMuted),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A row heading with an optional action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, 0, AppSpace.gutter, AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text(title, style: AppText.headingLg)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// `.chip` — a pill used for genres, filters and status.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.accent : AppColors.textSecondary;

    return Material(
      color: selected ? AppColors.accentAt(0.14) : AppColors.white(0.04),
      borderRadius: AppRadius.all(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.all(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: AppSpace.sm),
          decoration: BoxDecoration(
            borderRadius: AppRadius.all(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColors.accentAt(0.4) : AppColors.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: AppSpace.xs),
              ],
              Text(
                label,
                style: AppText.caption.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// States plainly which playback path the viewer ended up on.
class ShieldChip extends StatelessWidget {
  const ShieldChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentAt(0.14),
        borderRadius: AppRadius.all(AppRadius.pill),
        border: Border.all(color: AppColors.accentAt(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_rounded, size: 13, color: AppColors.accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.caption.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown where a list would be, when the list is empty.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.white(0.04),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
              child: Icon(icon, color: AppColors.accent, size: 26),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(title, style: AppText.headingSm, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.sm),
            Text(message, style: AppText.bodyMuted, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.xl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A pulsing placeholder block, used while a screen's first request is in flight.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 0.75).animate(_controller),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.all(widget.radius),
        ),
      ),
    );
  }
}

/// A skeleton shaped like a poster rail, so the layout does not jump on load.
class RailSkeleton extends StatelessWidget {
  const RailSkeleton({super.key, this.itemWidth = 132, this.itemHeight = 198});

  final double itemWidth;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          child: Skeleton(width: 150, height: 20),
        ),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: itemHeight + 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(
                  width: itemWidth,
                  height: itemHeight,
                  radius: AppRadius.md,
                ),
                const SizedBox(height: AppSpace.sm),
                Skeleton(width: itemWidth * 0.75, height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Consistent error presentation for a failed load.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Something went wrong',
        message: message,
        actionLabel: onRetry == null ? null : 'Try again',
        onAction: onRetry,
      );
}

/// A floating message that matches the design system rather than Material's default.
void showAppSnack(BuildContext context, String message, {bool success = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_rounded,
              size: 18,
              color: success ? AppColors.success : AppColors.accent,
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(message, style: AppText.label)),
          ],
        ),
      ),
    );
}
