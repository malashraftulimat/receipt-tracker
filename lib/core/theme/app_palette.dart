import 'package:flutter/material.dart';

/// Vibrant but eye-friendly palette used across the app.
class AppPalette {
  const AppPalette._();

  // Base surfaces
  static const Color background = Color(0xFF121824);
  static const Color backgroundDeep = Color(0xFF0D121D);
  static const Color surface = Color(0xFF1E2640);
  static const Color surfaceAlt = Color(0xFF252F52);
  static const Color surfaceSoft = Color(0xFF2C3760);
  static const Color border = Color(0x334C5C8A);

  // Text
  static const Color text = Color(0xFFF6F8FF);
  static const Color textMuted = Color(0xFFAFBAD8);
  static const Color textFaint = Color(0xFF7E8AAB);

  // Accents
  static const Color emerald = Color(0xFF2ECC71);
  static const Color mint = Color(0xFF55EFC4);
  static const Color amber = Color(0xFFFF9F43);
  static const Color yellow = Color(0xFFFFD166);
  static const Color violet = Color(0xFF6C5CE7);
  static const Color violetDeep = Color(0xFF8E44AD);
  static const Color cyan = Color(0xFF00CEC9);
  static const Color sky = Color(0xFF74B9FF);
  static const Color pink = Color(0xFFFF8FA3);
  static const Color coral = Color(0xFFFF7A7A);
  static const Color danger = Color(0xFFFF6B81);

  // Gradients
  static const LinearGradient budgetGradient = LinearGradient(
    colors: <Color>[emerald, yellow, amber],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: <Color>[violet, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient scanGradient = LinearGradient(
    colors: <Color>[cyan, Color(0xFF1DD1C3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: <Color>[emerald, mint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: <Color>[amber, yellow],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Distinct, soft category accents. Existing/custom categories fall back to
  /// the colour saved in Firestore.
  static Color categoryAccent(String? name, {Color? fallback}) {
    switch (name) {
      case '食費':
        return pink;
      case '外食':
        return const Color(0xFFFFA36C);
      case '日用品':
        return const Color(0xFFA78BFA);
      case '光熱費':
        return yellow;
      case '交通費':
        return sky;
      case '娯楽':
        return const Color(0xFFC084FC);
      case '医療・医薬品':
        return mint;
      case 'その他':
        return const Color(0xFF9AA8C7);
      default:
        return fallback ?? violet;
    }
  }

  static Color statusColor(String label) {
    if (label.contains('達成') || label.contains('順調')) return emerald;
    if (label.contains('注意') || label.contains('警告')) return amber;
    if (label.contains('超過') || label.contains('オーバー')) return danger;
    return violet;
  }

  static BoxDecoration card(
    BuildContext context, {
    Color? accent,
    double radius = 18,
    bool glow = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final highlighted = accent ?? (isDark ? border : outline);

    return BoxDecoration(
      color: isDark ? surface : Colors.white,
      gradient: isDark
          ? const LinearGradient(
              colors: <Color>[Color(0xFF232D50), Color(0xFF1E2640)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: accent?.withValues(alpha: isDark ? 0.42 : 0.3) ??
            highlighted.withValues(alpha: isDark ? 0.72 : 0.55),
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.06),
          blurRadius: glow ? 24 : 16,
          offset: const Offset(0, 8),
        ),
        if (glow && accent != null)
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
            blurRadius: 28,
            spreadRadius: 1,
          ),
      ],
    );
  }

  static BoxDecoration tintedPill(Color color, {double radius = 999}) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: <Color>[
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.12),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: color.withValues(alpha: 0.42)),
    );
  }
}
