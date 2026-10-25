import 'package:flutter/material.dart';

/// Single source of truth for animation durations and curves in the Pair design system.
class AppMotion {
  AppMotion._();

  // Durations
  static const Duration shortDuration = Duration(milliseconds: 150);
  static const Duration mediumDuration = Duration(milliseconds: 250);
  static const Duration longDuration = Duration(milliseconds: 400);

  // Curves
  static const Curve easeOutCubic = Curves.easeOutCubic;
  static const Curve easeInOutCubic = Curves.easeInOutCubic;

  /// Returns the given [duration] unless [MediaQueryData.disableAnimations] is enabled on the [context],
  /// in which case [Duration.zero] is returned to honor reduced motion preferences.
  static Duration responsiveDuration(BuildContext context, Duration duration) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return Duration.zero;
    }
    return duration;
  }
}
