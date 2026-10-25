import 'package:flutter/material.dart';

/// Single source of truth for color tokens across both Light and Dark themes.
class AppColors {
  AppColors._();

  // Brand Colors
  static const Color primarySeed = Color(0xFF5B5BD6); // Indigo
  static const Color accent = Color(0xFFFF7A45); // Flame / Streak

  // Light Palette
  static const Color lightBackground = Color(0xFFF7F7FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFFFFFFF);
  static const Color lightOutlineSubtle = Color(0xFFE6E6EE);
  static const Color lightTextPrimary = Color(0xFF14151A);
  static const Color lightTextSecondary = Color(0xFF5E6272);

  // Dark Palette (Near-black layered surfaces, never pure #000, never pure white text)
  static const Color darkBackground = Color(0xFF0E0F13);
  static const Color darkSurface = Color(0xFF16181D);
  static const Color darkSurfaceElevated = Color(0xFF1E2128);
  static const Color darkOutlineSubtle = Color(0xFF2A2D36);
  static const Color darkTextPrimary = Color(0xFFF2F3F7);
  static const Color darkTextSecondary = Color(0xFFA4A8B5);

  // Semantic Colors
  static const Color lightSuccess = Color(0xFF2E9E6B);
  static const Color darkSuccess = Color(0xFF38B27A);

  static const Color lightWarning = Color(0xFFE5A00D);
  static const Color darkWarning = Color(0xFFF2AF29);

  static const Color lightError = Color(0xFFD64545);
  static const Color darkError = Color(0xFFE55656);

  // Additional tokens for chat bubbles, gradients, and shimmers
  static const Color lightBubbleSelf = Color(0xFF5B5BD6);
  static const Color lightBubbleSelfOn = Color(0xFFFFFFFF);
  static const Color lightBubblePartner = Color(0xFFF0F1F7);
  static const Color lightBubblePartnerOn = Color(0xFF14151A);

  static const Color darkBubbleSelf = Color(0xFF5B5BD6);
  static const Color darkBubbleSelfOn = Color(0xFFFFFFFF);
  static const Color darkBubblePartner = Color(0xFF1E2128);
  static const Color darkBubblePartnerOn = Color(0xFFF2F3F7);

  static const Color lightGradientStart = Color(0xFF5B5BD6);
  static const Color lightGradientEnd = Color(0xFF7E7EE8);

  static const Color darkGradientStart = Color(0xFF4A4ABF);
  static const Color darkGradientEnd = Color(0xFF6B6BE0);

  static const Color lightShimmerBase = Color(0xFFE6E6EE);
  static const Color lightShimmerHighlight = Color(0xFFF7F7FB);

  static const Color darkShimmerBase = Color(0xFF1E2128);
  static const Color darkShimmerHighlight = Color(0xFF2A2D36);

  /// Generates the light ColorScheme seeded from primarySeed and customized with tokens.
  static ColorScheme get lightColorScheme {
    final base = ColorScheme.fromSeed(
      seedColor: primarySeed,
      brightness: Brightness.light,
    );

    return base.copyWith(
      primary: primarySeed,
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFFECECFA),
      onPrimaryContainer: const Color(0xFF232373),
      secondary: accent,
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFFFECE5),
      onSecondaryContainer: const Color(0xFF6E280C),
      tertiary: accent,
      surface: lightSurface,
      onSurface: lightTextPrimary,
      surfaceContainerHighest: lightSurfaceElevated,
      surfaceContainerLow: lightBackground,
      onSurfaceVariant: lightTextSecondary,
      outline: lightOutlineSubtle,
      outlineVariant: lightOutlineSubtle,
      error: lightError,
      onError: const Color(0xFFFFFFFF),
    );
  }

  /// Generates the dark ColorScheme seeded from primarySeed and customized with tokens.
  static ColorScheme get darkColorScheme {
    final base = ColorScheme.fromSeed(
      seedColor: primarySeed,
      brightness: Brightness.dark,
    );

    return base.copyWith(
      primary: primarySeed,
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFF383894),
      onPrimaryContainer: const Color(0xFFE4E4FB),
      secondary: accent,
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFF5C240E),
      onSecondaryContainer: const Color(0xFFFFD5C4),
      tertiary: accent,
      surface: darkSurface,
      onSurface: darkTextPrimary,
      surfaceContainerHighest: darkSurfaceElevated,
      surfaceContainerLow: darkBackground,
      onSurfaceVariant: darkTextSecondary,
      outline: darkOutlineSubtle,
      outlineVariant: darkOutlineSubtle,
      error: darkError,
      onError: const Color(0xFF3F0B0B),
    );
  }
}
