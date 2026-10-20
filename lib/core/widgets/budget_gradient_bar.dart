import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Smooth green → yellow → orange budget progress bar.
class BudgetGradientBar extends StatelessWidget {
  const BudgetGradientBar({
    super.key,
    required this.value,
    this.height = 10,
    this.trackColor,
  });

  final double value;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: trackColor ??
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppPalette.budgetGradient,
                    borderRadius: BorderRadius.circular(height),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppPalette.amber.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
