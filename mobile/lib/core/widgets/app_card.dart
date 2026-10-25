import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Design system standard card container with padding, border, and optional tap ripple.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? color;
  final BorderSide? border;
  final double? elevation;
  final bool isSelected;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.borderRadius,
    this.color,
    this.border,
    this.elevation,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveRadius = borderRadius ?? AppRadius.borderRadiusCard;
    final effectiveColor = color ??
        (isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
            : (theme.cardTheme.color ?? theme.colorScheme.surface));
    final effectiveBorder = border ??
        (isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2.0)
            : BorderSide(
                color: theme.colorScheme.outline,
                width: 1.0,
              ));

    Widget content = Padding(
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: effectiveRadius,
        child: InkWell(
          borderRadius: effectiveRadius,
          onTap: onTap,
          child: content,
        ),
      );
    }

    return Card(
      elevation: elevation ?? theme.cardTheme.elevation ?? 0,
      color: effectiveColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: effectiveRadius,
        side: effectiveBorder,
      ),
      child: content,
    );
  }
}
