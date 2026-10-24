import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local device preference model for notification type filtering.
class NotificationPreferences {
  final bool newMessage;
  final bool checkinNudge;
  final bool streakBroken;
  final bool matchFound;

  const NotificationPreferences({
    this.newMessage = true,
    this.checkinNudge = true,
    this.streakBroken = true,
    this.matchFound = true,
  });

  /// Checks if local notifications are enabled for the given type.
  bool isEnabled(String type) {
    switch (type) {
      case 'new_message':
        return newMessage;
      case 'checkin_nudge':
        return checkinNudge;
      case 'streak_broken':
        return streakBroken;
      case 'match_found':
        return matchFound;
      default:
        return true;
    }
  }

  NotificationPreferences copyWith({
    bool? newMessage,
    bool? checkinNudge,
    bool? streakBroken,
    bool? matchFound,
  }) {
    return NotificationPreferences(
      newMessage: newMessage ?? this.newMessage,
      checkinNudge: checkinNudge ?? this.checkinNudge,
      streakBroken: streakBroken ?? this.streakBroken,
      matchFound: matchFound ?? this.matchFound,
    );
  }
}

/// Riverpod notifier managing local notification preferences backed by [SharedPreferences].
class NotificationPreferencesNotifier extends Notifier<NotificationPreferences> {
  static const String keyNewMessage = 'notif_pref_new_message';
  static const String keyCheckinNudge = 'notif_pref_checkin_nudge';
  static const String keyStreakBroken = 'notif_pref_streak_broken';
  static const String keyMatchFound = 'notif_pref_match_found';

  @override
  NotificationPreferences build() {
    _loadFromPreferences();
    return const NotificationPreferences();
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = NotificationPreferences(
        newMessage: prefs.getBool(keyNewMessage) ?? true,
        checkinNudge: prefs.getBool(keyCheckinNudge) ?? true,
        streakBroken: prefs.getBool(keyStreakBroken) ?? true,
        matchFound: prefs.getBool(keyMatchFound) ?? true,
      );
    } catch (_) {
      // In tests or non-shared-preferences environments, keep default true values
    }
  }

  Future<void> toggleNewMessage(bool value) async {
    state = state.copyWith(newMessage: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyNewMessage, value);
    } catch (_) {}
  }

  Future<void> toggleCheckinNudge(bool value) async {
    state = state.copyWith(checkinNudge: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyCheckinNudge, value);
    } catch (_) {}
  }

  Future<void> toggleStreakBroken(bool value) async {
    state = state.copyWith(streakBroken: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyStreakBroken, value);
    } catch (_) {}
  }

  Future<void> toggleMatchFound(bool value) async {
    state = state.copyWith(matchFound: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyMatchFound, value);
    } catch (_) {}
  }
}

/// Provider for notification preferences.
final notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
  NotificationPreferencesNotifier.new,
);
