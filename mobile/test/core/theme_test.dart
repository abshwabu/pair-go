import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';

void main() {
  group('AppTheme Tests', () {
    test('Light theme properties are correctly configured', () {
      final light = AppTheme.lightTheme;

      expect(light.brightness, Brightness.light);
      expect(light.colorScheme.primary, AppTheme.primary);
      expect(light.colorScheme.secondary, AppTheme.secondary);
      expect(light.colorScheme.tertiary, AppTheme.tertiary);
      expect(light.colorScheme.surface, AppTheme.surfaceLight);
      expect(light.scaffoldBackgroundColor, AppTheme.backgroundLight);
      expect(light.useMaterial3, isTrue);

      expect(light.cardTheme.shape, isA<RoundedRectangleBorder>());
      expect(light.inputDecorationTheme.filled, isTrue);
    });

    test('Dark theme properties are correctly configured', () {
      final dark = AppTheme.darkTheme;

      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.primary, AppTheme.primary);
      expect(dark.colorScheme.secondary, AppTheme.secondary);
      expect(dark.colorScheme.tertiary, AppTheme.tertiary);
      expect(dark.colorScheme.surface, AppTheme.surfaceDark);
      expect(dark.scaffoldBackgroundColor, AppTheme.backgroundDark);
      expect(dark.useMaterial3, isTrue);

      expect(dark.cardTheme.shape, isA<RoundedRectangleBorder>());
      expect(dark.inputDecorationTheme.filled, isTrue);
    });

    test('Spacing and Radius constants are strictly positive and ordered', () {
      expect(AppSpacing.xxs, lessThan(AppSpacing.xs));
      expect(AppSpacing.xs, lessThan(AppSpacing.sm));
      expect(AppSpacing.sm, lessThan(AppSpacing.md));
      expect(AppSpacing.md, lessThan(AppSpacing.lg));
      expect(AppSpacing.lg, lessThan(AppSpacing.xl));
      expect(AppSpacing.xl, lessThan(AppSpacing.xxl));

      expect(AppRadius.sm, lessThan(AppRadius.md));
      expect(AppRadius.md, lessThan(AppRadius.lg));
      expect(AppRadius.lg, lessThan(AppRadius.xl));
      expect(AppRadius.xl, lessThan(AppRadius.full));
    });

    test('Typography styles define expected sizes and weights', () {
      expect(AppTypography.displayLarge.fontSize, 32.0);
      expect(AppTypography.headlineMedium.fontSize, 20.0);
      expect(AppTypography.bodyLarge.fontSize, 16.0);
      expect(AppTypography.bodySmall.fontSize, 12.0);
    });
  });
}
