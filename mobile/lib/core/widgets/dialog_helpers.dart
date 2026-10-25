import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Displays a design-system styled modal bottom sheet.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool isDismissible = true,
  bool enableDrag = true,
  bool isScrollControlled = false,
}) {
  final theme = Theme.of(context);

  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
    ),
    builder: (ctx) {
      if (title != null) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                child: Text(
                  title,
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Flexible(child: builder(ctx)),
            ],
          ),
        );
      }
      return builder(ctx);
    },
  );
}

/// Displays a design-system styled modal alert dialog.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final theme = Theme.of(context);

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) {
      return Dialog(
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusLg,
        ),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: builder(ctx),
        ),
      );
    },
  );
}

/// Shows a floating snackbar styled with design system tokens.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar({
  required BuildContext context,
  required String message,
  bool isError = false,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  final bg = isError ? colorScheme.error : colorScheme.onSurface;
  final fg = isError ? colorScheme.onError : colorScheme.surface;

  return messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: AppTypography.bodySmall.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusMd,
      ),
      duration: duration,
      action: actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: colorScheme.primary,
              onPressed: onAction,
            )
          : null,
    ),
  );
}
