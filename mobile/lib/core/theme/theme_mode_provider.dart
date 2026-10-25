import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kThemeModeKey = 'theme_mode';

/// Parses a string value from storage into a [ThemeMode].
ThemeMode parseThemeMode(String? raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}

/// Serializes [ThemeMode] to string for storage.
String themeModeToString(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

/// Overridable initial theme mode provider populated before [runApp] to eliminate flash.
final initialThemeModeProvider = Provider<ThemeMode>((ref) {
  return ThemeMode.system;
});

/// Riverpod Notifier managing [ThemeMode] and persisting choices via SharedPreferences.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return ref.watch(initialThemeModeProvider);
  }

  /// Updates and persists the chosen [ThemeMode].
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kThemeModeKey, themeModeToString(mode));
    } catch (_) {}
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
