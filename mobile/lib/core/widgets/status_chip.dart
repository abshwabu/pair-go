import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extension.dart';
import '../theme/app_typography.dart';

enum StatusChipVariant {
  success,
  warning,
  error,
  info,
  streak,
}

/// Compact status chip badge styled with design system semantic tokens.
class StatusChip extends StatelessWidget {
  final String label;
  final StatusChipVariant variant;
  final IconData? icon;

  const StatusChip({
    super.key,
    required this.label,
    this.variant = StatusChipVariant.info,
    this.icon,
  });

  const StatusChip.success({
    super.key,
    required this.label,
    this.icon,
  }) : variant = StatusChipVariant.success;

  const StatusChip.warning({
    super.key,
    required this.label,
    this.icon,
  }) : variant = StatusChipVariant.warning;

  const StatusChip.error({
    super.key,
    required this.label,
    this.icon,
  }) : variant = StatusChipVariant.error;

  const StatusChip.streak({
    super.key,
    required this.label,
    this.icon = Icons.local_fire_department_rounded,
  }) : variant = StatusChipVariant.streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = context.appColors;

    Color bg;
    Color fg;

    switch (variant) {
      case StatusChipVariant.success:
        bg = appColors.success.withValues(alpha: 0.15);
        fg = appColors.success;
        break;
      case StatusChipVariant.warning:
        bg = appColors.warning.withValues(alpha: 0.15);
        fg = appColors.warning;
        break;
      case StatusChipVariant.error:
        bg = colorScheme.error.withValues(alpha: 0.15);
        fg = colorScheme.error;
        break;
      case StatusChipVariant.streak:
        bg = appColors.flameBackground;
        fg = appColors.flame;
        break;
      case StatusChipVariant.info:
        bg = colorScheme.primary.withValues(alpha: 0.12);
        fg = colorScheme.primary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
