import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Type scale, mirroring the web's `heading-xl` / `heading-lg` / `section-label`
/// helpers. Negative tracking on headings is what stops the app looking like a
/// default Material project.
class AppText {
  const AppText._();

  static const _family = 'Inter';

  static const display = TextStyle(
    fontFamily: _family,
    fontSize: 30,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    color: AppColors.textPrimary,
  );

  static const headingLg = TextStyle(
    fontFamily: _family,
    fontSize: 21,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  static const headingSm = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const bodyMuted = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const label = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const caption = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// `.section-label` — the tracked uppercase eyebrow above a heading.
  static const eyebrow = TextStyle(
    fontFamily: _family,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.8,
    color: AppColors.textSecondary,
  );

  static const button = TextStyle(
    fontFamily: _family,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData build() {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.bg,
      secondary: AppColors.accentSoft,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      fontFamily: 'Inter',
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.headingLg,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      textTheme: const TextTheme(
        displaySmall: AppText.display,
        titleLarge: AppText.headingLg,
        titleMedium: AppText.headingSm,
        bodyLarge: AppText.body,
        bodyMedium: AppText.bodyMuted,
        labelLarge: AppText.label,
        labelSmall: AppText.caption,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.bg,
          textStyle: AppText.button,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.white(0.05),
          textStyle: AppText.button,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
          side: const BorderSide(color: AppColors.hairlineStrong),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: AppText.button,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white(0.04),
        hintStyle: AppText.bodyMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.lg,
        ),
        border: _inputBorder(AppColors.hairline),
        enabledBorder: _inputBorder(AppColors.hairline),
        focusedBorder: _inputBorder(AppColors.accentAt(0.6)),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: AppText.label,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
        insetPadding: const EdgeInsets.all(AppSpace.lg),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgSoft,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.border,
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppText.label,
        unselectedLabelStyle: AppText.label,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.accent, width: 2),
          insets: EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
        borderRadius: AppRadius.all(AppRadius.md),
        borderSide: BorderSide(color: color),
      );
}
