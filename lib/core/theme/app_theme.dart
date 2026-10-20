import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Centralised Material 3 theme with a vibrant, low-glare dark palette.
class AppTheme {
  const AppTheme._();

  static const Color seed = AppPalette.violet;

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = _scheme(brightness);

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? AppPalette.background : const Color(0xFFF3F6FC),
      canvasColor: isDark ? AppPalette.background : const Color(0xFFF3F6FC),
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
          bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.45),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.15,
            fontWeight: FontWeight.w600,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppPalette.surfaceAlt.withValues(alpha: 0.82)
            : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppPalette.surfaceAlt : Colors.white,
        selectedColor: scheme.tertiary.withValues(alpha: 0.22),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.tertiary,
          minimumSize: const Size(0, 46),
          side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.tertiary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.tertiary,
        foregroundColor: Colors.white,
        elevation: isDark ? 6 : 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? AppPalette.surface : Colors.white,
        indicatorColor: scheme.tertiary.withValues(alpha: 0.24),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.tertiary : scheme.onSurfaceVariant,
            size: selected ? 25 : 23,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.tertiary : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? AppPalette.surface : Colors.white,
        indicatorColor: scheme.tertiary.withValues(alpha: 0.24),
        selectedIconTheme: IconThemeData(color: scheme.tertiary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.tertiary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppPalette.surfaceSoft : const Color(0xFF252F52),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.tertiary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppPalette.surface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppPalette.surface : Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: isDark ? AppPalette.surface : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.tertiary,
        textColor: scheme.onSurface,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.tertiary
                : Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? Colors.white
                : scheme.onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.tertiary.withValues(alpha: 0.38)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  static ColorScheme _scheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: AppPalette.violet,
      brightness: brightness,
    );

    if (!isDark) {
      return base.copyWith(
        primary: const Color(0xFF149A57),
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFD8F8E8),
        onPrimaryContainer: const Color(0xFF063B21),
        secondary: const Color(0xFFD97706),
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFFFE8CC),
        onSecondaryContainer: const Color(0xFF4A2600),
        tertiary: const Color(0xFF5A4BD8),
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFE7E3FF),
        onTertiaryContainer: const Color(0xFF1D174F),
        error: const Color(0xFFD64560),
        surface: Colors.white,
        onSurface: const Color(0xFF171D2E),
        surfaceContainerHighest: const Color(0xFFE8EDF8),
        onSurfaceVariant: const Color(0xFF5B6685),
        outline: const Color(0xFFA6B0C9),
        outlineVariant: const Color(0xFFD9E0EF),
      );
    }

    return base.copyWith(
      primary: AppPalette.emerald,
      onPrimary: const Color(0xFF061D12),
      primaryContainer: const Color(0xFF1A4D35),
      onPrimaryContainer: const Color(0xFFC9FFE1),
      secondary: AppPalette.amber,
      onSecondary: const Color(0xFF2A1600),
      secondaryContainer: const Color(0xFF593510),
      onSecondaryContainer: const Color(0xFFFFDFC1),
      tertiary: AppPalette.violet,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFF302A63),
      onTertiaryContainer: const Color(0xFFE3DEFF),
      error: AppPalette.danger,
      onError: const Color(0xFF2A0008),
      errorContainer: const Color(0xFF5B1F2C),
      onErrorContainer: const Color(0xFFFFD9DF),
      surface: AppPalette.surface,
      onSurface: AppPalette.text,
      surfaceContainerHighest: AppPalette.surfaceAlt,
      onSurfaceVariant: AppPalette.textMuted,
      outline: const Color(0xFF4B5A80),
      outlineVariant: const Color(0xFF2E3A5C),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppPalette.text,
      onInverseSurface: AppPalette.background,
      inversePrimary: const Color(0xFF149A57),
    );
  }
}
