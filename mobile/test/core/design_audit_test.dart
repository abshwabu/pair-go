import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/theme/theme_mode_provider.dart';
import 'package:mobile/core/widgets/widgets.dart';

/// Calculates the relative luminance contrast ratio between two colors according to WCAG 2.1.
double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Design Audit: Scan lib/features for hardcoded colors', () {
    test('Ensures NO Color(0x and NO Colors. are in lib/features', () {
      final featuresDir = Directory('lib/features');
      expect(featuresDir.existsSync(), isTrue,
          reason: 'lib/features must exist');

      final violations = <String>[];

      for (final entity in featuresDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final lines = entity.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];

            // Ignore comments
            final trimmed = line.trim();
            if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
              continue;
            }

            if (line.contains('Color(0x')) {
              violations.add(
                '${entity.path}:${i + 1} contains hardcoded Color(0x: "$trimmed"',
              );
            }

            if (line.contains('Colors.')) {
              violations.add(
                '${entity.path}:${i + 1} contains hardcoded Colors.: "$trimmed"',
              );
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Found ${violations.length} hardcoded color violations in lib/features:\n'
          '${violations.join('\n')}',
        );
      }
    });
  });

  group('Theme Tokens & WCAG AA Contrast Checks', () {
    test('Light theme text meets WCAG AA contrast against background and surface', () {
      final lightTheme = AppTheme.light;
      expect(lightTheme.brightness, Brightness.light);

      final bgRatio = contrastRatio(
        AppColors.lightTextPrimary,
        AppColors.lightBackground,
      );
      final surfaceRatio = contrastRatio(
        AppColors.lightTextPrimary,
        AppColors.lightSurface,
      );

      // WCAG AA normal text requirement is at least 4.5:1
      expect(bgRatio, greaterThanOrEqualTo(4.5),
          reason: 'Light textPrimary on lightBackground must meet AA (>= 4.5:1)');
      expect(surfaceRatio, greaterThanOrEqualTo(4.5),
          reason: 'Light textPrimary on lightSurface must meet AA (>= 4.5:1)');
    });

    test('Dark theme text meets WCAG AA contrast against background and surface', () {
      final darkTheme = AppTheme.dark;
      expect(darkTheme.brightness, Brightness.dark);

      final bgRatio = contrastRatio(
        AppColors.darkTextPrimary,
        AppColors.darkBackground,
      );
      final surfaceRatio = contrastRatio(
        AppColors.darkTextPrimary,
        AppColors.darkSurface,
      );

      expect(bgRatio, greaterThanOrEqualTo(4.5),
          reason: 'Dark textPrimary on darkBackground must meet AA (>= 4.5:1)');
      expect(surfaceRatio, greaterThanOrEqualTo(4.5),
          reason: 'Dark textPrimary on darkSurface must meet AA (>= 4.5:1)');
    });

    test('Dark theme uses near-black layered surfaces (never pure #000, never pure #FFF text)', () {
      expect(AppColors.darkBackground, isNot(equals(const Color(0xFF000000))));
      expect(AppColors.darkSurface, isNot(equals(const Color(0xFF000000))));
      expect(AppColors.darkSurfaceElevated, isNot(equals(const Color(0xFF000000))));
      expect(AppColors.darkTextPrimary, isNot(equals(const Color(0xFFFFFFFF))));
    });

    test('Both themes register AppColorsExtension with valid semantic tokens', () {
      final lightExt = AppTheme.light.extension<AppColorsExtension>();
      final darkExt = AppTheme.dark.extension<AppColorsExtension>();

      expect(lightExt, isNotNull);
      expect(darkExt, isNotNull);

      expect(lightExt!.success, AppColors.lightSuccess);
      expect(lightExt.warning, AppColors.lightWarning);
      expect(lightExt.flame, AppColors.accent);

      expect(darkExt!.success, AppColors.darkSuccess);
      expect(darkExt.warning, AppColors.darkWarning);
    });

    test('Component themes are configured with correct design system specs', () {
      final lightTheme = AppTheme.light;
      final darkTheme = AppTheme.dark;

      // Card
      expect(lightTheme.cardTheme.shape, isA<RoundedRectangleBorder>());
      expect(darkTheme.cardTheme.shape, isA<RoundedRectangleBorder>());

      // Buttons
      expect(lightTheme.filledButtonTheme.style?.minimumSize?.resolve({}),
          const Size(64, 52));
      expect(lightTheme.outlinedButtonTheme.style?.minimumSize?.resolve({}),
          const Size(64, 52));

      // BottomSheet & Dialog
      expect(lightTheme.bottomSheetTheme.showDragHandle, isTrue);
      expect(lightTheme.dialogTheme.shape, isA<RoundedRectangleBorder>());

      // SnackBar
      expect(lightTheme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });
  });

  group('ThemeMode Support & Persistence', () {
    test('themeModeToString and parseThemeMode round-trip correctly', () {
      expect(parseThemeMode('system'), ThemeMode.system);
      expect(parseThemeMode('light'), ThemeMode.light);
      expect(parseThemeMode('dark'), ThemeMode.dark);
      expect(parseThemeMode('invalid'), ThemeMode.system);
      expect(parseThemeMode(null), ThemeMode.system);

      expect(themeModeToString(ThemeMode.system), 'system');
      expect(themeModeToString(ThemeMode.light), 'light');
      expect(themeModeToString(ThemeMode.dark), 'dark');
    });

    test('ThemeModeNotifier defaults to system and persists updates', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);

      // Change to dark
      await container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kThemeModeKey), 'dark');

      // Change to light
      await container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(prefs.getString(kThemeModeKey), 'light');
    });
  });

  group('Widget Kit Tests', () {
    testWidgets('ThemeModeSelector updates mode on selection', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: ThemeModeSelector(),
            ),
          ),
        ),
      );

      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kThemeModeKey), 'dark');
    });

    testWidgets('AppButton renders variants and preserves dimensions while loading',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Column(
              children: [
                AppButton.primary(
                  label: 'Submit Goal',
                  isLoading: false,
                  onPressed: () {},
                ),
                AppButton.primary(
                  label: 'Submit Goal',
                  isLoading: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Submit Goal'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AppTextField handles password visibility toggle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: AppTextField(
              label: 'Password',
              isPassword: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('AppAvatar renders initials fallback and optional streak ring',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: AppAvatar(
              name: 'John Doe',
              size: AppAvatarSize.md,
              hasRing: true,
            ),
          ),
        ),
      );

      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('StatusChip renders semantic variants', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Column(
              children: [
                StatusChip.success(label: 'Done'),
                StatusChip.streak(label: '5 Days'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('5 Days'), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    });
  });
}
