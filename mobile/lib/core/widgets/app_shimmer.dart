import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extension.dart';

/// Design system shimmer wrapper honoring theme colors and reduced-motion settings.
class AppShimmer extends StatelessWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  const AppShimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  /// Single placeholder box with customizable width, height, and radius.
  static Widget box({
    double? width,
    double? height,
    BorderRadius? borderRadius,
  }) {
    return Builder(
      builder: (context) {
        final appColors = context.appColors;
        final base = appColors.shimmerBase;
        final highlight = appColors.shimmerHighlight;
        final radius = borderRadius ?? AppRadius.borderRadiusSm;

        final placeholder = Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: radius,
          ),
        );

        if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
          return placeholder;
        }

        return Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: placeholder,
        );
      },
    );
  }

  /// Shimmer placeholder representing a standard list tile row.
  static Widget listRow() {
    return Builder(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              AppShimmer.box(
                width: 44,
                height: 44,
                borderRadius: AppRadius.borderRadiusFull,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppShimmer.box(
                      width: double.infinity,
                      height: 14,
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppShimmer.box(
                      width: 140,
                      height: 12,
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shimmer placeholder representing a card.
  static Widget card({double height = 120}) {
    return Builder(
      builder: (context) {
        return AppShimmer.box(
          width: double.infinity,
          height: height,
          borderRadius: AppRadius.borderRadiusCard,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }

    final appColors = context.appColors;
    return Shimmer.fromColors(
      baseColor: baseColor ?? appColors.shimmerBase,
      highlightColor: highlightColor ?? appColors.shimmerHighlight,
      child: child,
    );
  }
}
