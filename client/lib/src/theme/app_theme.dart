import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color seedColor = Color(0xFF3658D9);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      contrastLevel: 0.1,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    ),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
      contrastLevel: 0.1,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    ),
  );

  static ThemeData _build(ColorScheme colors) {
    final base = ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme;

    return base.copyWith(
      scaffoldBackgroundColor: colors.surfaceContainerLowest,
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -2.4,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
        displayMedium: text.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.8,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
        headlineLarge: text.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
