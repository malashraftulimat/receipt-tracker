import 'package:flutter/widgets.dart';

/// Layout breakpoints (Material 3 window size classes, simplified).
class Breakpoints {
  const Breakpoints._();

  static const double compact = 0;      // phones
  static const double medium = 720;     // tablets / small windows
  static const double expanded = 1100;  // desktop
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  bool get isCompact => screenWidth < Breakpoints.medium;

  bool get isMedium =>
      screenWidth >= Breakpoints.medium && screenWidth < Breakpoints.expanded;

  bool get isExpanded => screenWidth >= Breakpoints.expanded;

  /// Horizontal page padding that grows with the window size.
  double get pagePadding => isExpanded ? 32 : (isMedium ? 24 : 16);

  /// Column count for a receipt-card grid.
  int get receiptGridColumns {
    if (isExpanded) return 4;
    if (isMedium) return 3;
    if (screenWidth < 380) return 1;
    return 2;
  }
}
