import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant {
  primary,
  secondary,
  tonal,
  text,
}

/// Standard button for the Pair design system with multiple variants,
/// loading state preserving width, disabled state, and leading icon support.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? leadingIcon;
  final bool isFullWidth;
  final double height;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.leadingIcon,
    this.isFullWidth = true,
    this.height = 52.0,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.leadingIcon,
    this.isFullWidth = true,
    this.height = 52.0,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.leadingIcon,
    this.isFullWidth = true,
    this.height = 52.0,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.tonal({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.leadingIcon,
    this.isFullWidth = true,
    this.height = 52.0,
  }) : variant = AppButtonVariant.tonal;

  const AppButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.leadingIcon,
    this.isFullWidth = false,
    this.height = 52.0,
  }) : variant = AppButtonVariant.text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = onPressed != null && !isLoading;

    Color backgroundColor;
    Color foregroundColor;
    BorderSide? borderSide;

    switch (variant) {
      case AppButtonVariant.primary:
        backgroundColor = colorScheme.primary;
        foregroundColor = colorScheme.onPrimary;
        break;
      case AppButtonVariant.secondary:
        backgroundColor = Colors.transparent;
        foregroundColor = colorScheme.primary;
        borderSide = BorderSide(color: colorScheme.outline, width: 1.5);
        break;
      case AppButtonVariant.tonal:
        backgroundColor = colorScheme.primaryContainer;
        foregroundColor = colorScheme.onPrimaryContainer;
        break;
      case AppButtonVariant.text:
        backgroundColor = Colors.transparent;
        foregroundColor = colorScheme.primary;
        break;
    }

    final effectiveShape = RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusMd,
      side: borderSide ?? BorderSide.none,
    );

    final content = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 20),
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ],
    );

    // Keep the layout dimensions constant while showing the spinner
    final buttonContent = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: isLoading ? 0.0 : 1.0,
          child: content,
        ),
        if (isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          ),
      ],
    );

    Widget button;

    switch (variant) {
      case AppButtonVariant.primary:
        button = FilledButton(
          onPressed: isEnabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            disabledBackgroundColor: colorScheme.outline,
            disabledForegroundColor: colorScheme.onSurfaceVariant,
            shape: effectiveShape,
            minimumSize: Size(isFullWidth ? double.infinity : kMinInteractiveDimension, height),
            elevation: 0,
          ),
          child: buttonContent,
        );
        break;

      case AppButtonVariant.secondary:
        button = OutlinedButton(
          onPressed: isEnabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor,
            side: borderSide,
            shape: effectiveShape,
            minimumSize: Size(isFullWidth ? double.infinity : kMinInteractiveDimension, height),
            elevation: 0,
          ),
          child: buttonContent,
        );
        break;

      case AppButtonVariant.tonal:
        button = FilledButton.tonal(
          onPressed: isEnabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            shape: effectiveShape,
            minimumSize: Size(isFullWidth ? double.infinity : kMinInteractiveDimension, height),
            elevation: 0,
          ),
          child: buttonContent,
        );
        break;

      case AppButtonVariant.text:
        button = TextButton(
          onPressed: isEnabled ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor,
            shape: effectiveShape,
            minimumSize: Size(isFullWidth ? double.infinity : kMinInteractiveDimension, height),
          ),
          child: buttonContent,
        );
        break;
    }

    if (isFullWidth) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }
}
