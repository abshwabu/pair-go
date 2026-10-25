import 'package:flutter/material.dart';

import '../theme/app_theme_extension.dart';
import '../theme/app_typography.dart';

enum AppAvatarSize {
  sm(32.0, 16.0, 12.0),
  md(44.0, 22.0, 16.0),
  lg(56.0, 28.0, 20.0),
  xl(72.0, 36.0, 26.0);

  final double diameter;
  final double radius;
  final double fontSize;

  const AppAvatarSize(this.diameter, this.radius, this.fontSize);
}

/// Design system avatar widget featuring network image caching, initials fallback,
/// optional accent/streak ring, and standard sizing tokens.
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final ImageProvider? image;
  final String? name;
  final AppAvatarSize size;
  final bool hasRing;
  final Color? ringColor;
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    this.imageUrl,
    this.image,
    this.name,
    this.size = AppAvatarSize.md,
    this.hasRing = false,
    this.ringColor,
    this.onTap,
  });

  String _getInitials() {
    if (name == null || name!.trim().isEmpty) return '?';
    final parts = name!.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appColors = context.appColors;

    final effectiveRingColor = ringColor ?? appColors.flame;
    final initials = _getInitials();

    final effectiveImage = image ??
        ((imageUrl != null && imageUrl!.isNotEmpty)
            ? NetworkImage(imageUrl!)
            : null);

    Widget avatar = CircleAvatar(
      radius: size.radius,
      backgroundColor: colorScheme.primaryContainer,
      backgroundImage: effectiveImage,
      child: (effectiveImage == null)
          ? Text(
              initials,
              style: AppTypography.labelLarge.copyWith(
                fontSize: size.fontSize,
                fontWeight: FontWeight.w700,
                color: colorScheme.onPrimaryContainer,
              ),
            )
          : null,
    );

    if (hasRing) {
      avatar = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: effectiveRingColor,
            width: 2.0,
          ),
        ),
        child: avatar,
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }

    return avatar;
  }
}
