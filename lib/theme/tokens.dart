import 'package:flutter/material.dart';

/// The stream-sync design tokens, translated for mobile.
///
/// Colours and radii come straight from the web `tailwind.config.js` so the phone
/// app, the TV app and the site read as one product. Keep them in sync.
class AppColors {
  const AppColors._();

  /// Page background (near black).
  static const bg = Color(0xFF0B0B0E);

  /// Slightly raised background.
  static const bgSoft = Color(0xFF101015);

  /// Card and sheet surfaces.
  static const surface = Color(0xFF15151B);

  /// A surface sitting on top of another surface.
  static const surfaceHigh = Color(0xFF1D1D25);

  /// Borders and dividers.
  static const border = Color(0xFF23232B);

  static const accent = Color(0xFFE9B949);
  static const accentHover = Color(0xFFD4A43A);
  static const accentSoft = Color(0xFFF5D48A);

  static const textPrimary = Color(0xFFF4F4F5);
  static const textSecondary = Color(0xFF9B9BA5);

  static const danger = Color(0xFFE5484D);
  static const success = Color(0xFF3DD68C);

  /// `white/[0.06]` — the hairline the web cards use.
  static const hairline = Color(0x0FFFFFFF);
  static const hairlineStrong = Color(0x1FFFFFFF);

  static Color white(double opacity) => Colors.white.withValues(alpha: opacity);

  static Color black(double opacity) => Colors.black.withValues(alpha: opacity);

  static Color accentAt(double opacity) =>
      accent.withValues(alpha: opacity);
}

/// Corner radii, from the web `rounded-lg` / `rounded-xl` / `rounded-2xl` scale.
class AppRadius {
  const AppRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
  static const pill = 999.0;

  static BorderRadius all(double radius) => BorderRadius.circular(radius);
}

/// A 4pt spacing scale. Using named steps keeps rhythm consistent across screens.
class AppSpace {
  const AppSpace._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Standard horizontal page gutter.
  static const gutter = 20.0;
}

/// Motion, matching the web `ease-out-expo` token.
class AppMotion {
  const AppMotion._();

  static const curve = Cubic(0.16, 1, 0.3, 1);
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
}

/// Reusable decorations so surfaces are described once.
class AppDecoration {
  const AppDecoration._();

  /// `.surface` — a filled panel with a hairline edge.
  static BoxDecoration surface({
    double radius = AppRadius.lg,
    Color? color,
    Color? borderColor,
  }) =>
      BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: AppRadius.all(radius),
        border: Border.all(color: borderColor ?? AppColors.hairline),
      );

  /// `.glass-card` — the translucent panel used for sheets and modals.
  static BoxDecoration glass({double radius = AppRadius.lg}) => BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: AppRadius.all(radius),
        border: Border.all(color: AppColors.hairlineStrong),
      );

  /// `shadow-card` — a soft lift for poster artwork.
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: AppColors.black(0.4),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: AppColors.black(0.55),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// `shadow-glow` — the accent halo on a primary action.
  static List<BoxShadow> get accentGlow => [
        BoxShadow(
          color: AppColors.accentAt(0.35),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
