import 'package:flutter/material.dart';

import 'app_colors.dart';

/// ThemeExtension carrying custom semantic tokens and surface variants.
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color success;
  final Color warning;
  final Color flame;
  final Color flameBackground;
  final Color bubbleSelf;
  final Color bubbleSelfOn;
  final Color bubblePartner;
  final Color bubblePartnerOn;
  final Color outlineSubtle;
  final Color surfaceElevated;
  final Color gradientStart;
  final Color gradientEnd;
  final Color shimmerBase;
  final Color shimmerHighlight;

  const AppColorsExtension({
    required this.success,
    required this.warning,
    required this.flame,
    required this.flameBackground,
    required this.bubbleSelf,
    required this.bubbleSelfOn,
    required this.bubblePartner,
    required this.bubblePartnerOn,
    required this.outlineSubtle,
    required this.surfaceElevated,
    required this.gradientStart,
    required this.gradientEnd,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  /// Preset for Light mode.
  static const AppColorsExtension light = AppColorsExtension(
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
    flame: AppColors.accent,
    flameBackground: Color(0xFFFFECE5),
    bubbleSelf: AppColors.lightBubbleSelf,
    bubbleSelfOn: AppColors.lightBubbleSelfOn,
    bubblePartner: AppColors.lightBubblePartner,
    bubblePartnerOn: AppColors.lightBubblePartnerOn,
    outlineSubtle: AppColors.lightOutlineSubtle,
    surfaceElevated: AppColors.lightSurfaceElevated,
    gradientStart: AppColors.lightGradientStart,
    gradientEnd: AppColors.lightGradientEnd,
    shimmerBase: AppColors.lightShimmerBase,
    shimmerHighlight: AppColors.lightShimmerHighlight,
  );

  /// Preset for Dark mode.
  static const AppColorsExtension dark = AppColorsExtension(
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    flame: Color(0xFFFF9466),
    flameBackground: Color(0xFF381A0E),
    bubbleSelf: AppColors.darkBubbleSelf,
    bubbleSelfOn: AppColors.darkBubbleSelfOn,
    bubblePartner: AppColors.darkBubblePartner,
    bubblePartnerOn: AppColors.darkBubblePartnerOn,
    outlineSubtle: AppColors.darkOutlineSubtle,
    surfaceElevated: AppColors.darkSurfaceElevated,
    gradientStart: AppColors.darkGradientStart,
    gradientEnd: AppColors.darkGradientEnd,
    shimmerBase: AppColors.darkShimmerBase,
    shimmerHighlight: AppColors.darkShimmerHighlight,
  );

  @override
  AppColorsExtension copyWith({
    Color? success,
    Color? warning,
    Color? flame,
    Color? flameBackground,
    Color? bubbleSelf,
    Color? bubbleSelfOn,
    Color? bubblePartner,
    Color? bubblePartnerOn,
    Color? outlineSubtle,
    Color? surfaceElevated,
    Color? gradientStart,
    Color? gradientEnd,
    Color? shimmerBase,
    Color? shimmerHighlight,
  }) {
    return AppColorsExtension(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      flame: flame ?? this.flame,
      flameBackground: flameBackground ?? this.flameBackground,
      bubbleSelf: bubbleSelf ?? this.bubbleSelf,
      bubbleSelfOn: bubbleSelfOn ?? this.bubbleSelfOn,
      bubblePartner: bubblePartner ?? this.bubblePartner,
      bubblePartnerOn: bubblePartnerOn ?? this.bubblePartnerOn,
      outlineSubtle: outlineSubtle ?? this.outlineSubtle,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    );
  }

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) {
      return this;
    }

    return AppColorsExtension(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      flame: Color.lerp(flame, other.flame, t) ?? flame,
      flameBackground: Color.lerp(flameBackground, other.flameBackground, t) ?? flameBackground,
      bubbleSelf: Color.lerp(bubbleSelf, other.bubbleSelf, t) ?? bubbleSelf,
      bubbleSelfOn: Color.lerp(bubbleSelfOn, other.bubbleSelfOn, t) ?? bubbleSelfOn,
      bubblePartner: Color.lerp(bubblePartner, other.bubblePartner, t) ?? bubblePartner,
      bubblePartnerOn: Color.lerp(bubblePartnerOn, other.bubblePartnerOn, t) ?? bubblePartnerOn,
      outlineSubtle: Color.lerp(outlineSubtle, other.outlineSubtle, t) ?? outlineSubtle,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t) ?? surfaceElevated,
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t) ?? gradientStart,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t) ?? gradientEnd,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t) ?? shimmerBase,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t) ?? shimmerHighlight,
    );
  }
}

/// Convenience extension on [BuildContext] to access [AppColorsExtension].
extension AppThemeContextExtension on BuildContext {
  AppColorsExtension get appColors =>
      Theme.of(this).extension<AppColorsExtension>() ?? AppColorsExtension.light;

  /// Semantic tokens alias avoiding any substring matching with Material Colors.
  AppColorsExtension get tokens => appColors;
}
