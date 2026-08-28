import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hydrowin/core/theme/hw_colors.dart';
import 'package:hydrowin/domain/models/sensor_status_level.dart';

export 'package:hydrowin/domain/models/sensor_status_level.dart';

abstract final class AppTheme {
  static const fontFamily = 'NotoSans';

  static ThemeData get light => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme(
          brightness: Brightness.light,
          primary: HwColors.primary,
          onPrimary: HwColors.onPrimary,
          secondary: HwColors.primary,
          onSecondary: HwColors.onPrimary,
          error: HwColors.critical,
          onError: Colors.white,
          surface: HwColors.lightSurface,
          onSurface: HwColors.lightText,
          onSurfaceVariant: HwColors.lightMuted,
          outline: HwColors.lightBorder,
          outlineVariant: HwColors.lightBorder,
          surfaceContainerHighest: HwColors.lightElevated,
          surfaceContainerHigh: HwColors.lightElevated,
          surfaceContainer: HwColors.lightCanvas,
          surfaceContainerLow: HwColors.lightCanvas,
          surfaceContainerLowest: HwColors.lightSurface,
        ),
        scaffold: HwColors.lightCanvas,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: HwColors.primary,
          onPrimary: HwColors.onPrimary,
          secondary: HwColors.primary,
          onSecondary: HwColors.onPrimary,
          error: HwColors.critical,
          onError: HwColors.canvas,
          surface: HwColors.surface,
          onSurface: HwColors.textPrimary,
          onSurfaceVariant: HwColors.textMuted,
          outline: HwColors.border,
          outlineVariant: HwColors.border,
          surfaceContainerHighest: HwColors.elevated,
          surfaceContainerHigh: HwColors.elevated,
          surfaceContainer: HwColors.surface,
          surfaceContainerLow: HwColors.canvas,
          surfaceContainerLowest: HwColors.canvas,
        ),
        scaffold: HwColors.canvas,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scaffold,
    );

    final text = base.textTheme.apply(
      fontFamily: fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return base.copyWith(
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        labelSmall: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: text.titleLarge?.copyWith(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
        ),
        margin: const EdgeInsets.only(bottom: 8),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: fontFamily,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: fontFamily,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outline.withValues(alpha: 0.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static Color statusColor(SensorStatusLevel level, BuildContext context) {
    return switch (level) {
      SensorStatusLevel.ok => HwColors.ok,
      SensorStatusLevel.warning => HwColors.warn,
      SensorStatusLevel.critical => HwColors.critical,
      SensorStatusLevel.offline => HwColors.offline,
    };
  }
}
