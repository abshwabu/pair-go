import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local device preference model for notification type filtering.
class NotificationPreferences {
  final bool newMessage;
  final bool checkinNudge;
  final bool streakBroken;
  final bool matchProposed;
  final bool matchConfirmed;
  final bool matchDeclined;

  const NotificationPreferences({
    this.newMessage = true,
    this.checkinNudge = true,
    this.streakBroken = true,
    this.matchProposed = true,
    this.matchConfirmed = true,
    this.matchDeclined = true,
  });

  /// Backwards compatibility getter
  bool get matchFound => matchConfirmed;

  /// Checks if local notifications are enabled for the given type.
  bool isEnabled(String type) {
    switch (type) {
      case 'new_message':
        return newMessage;
      case 'checkin_nudge':
        return checkinNudge;
      case 'streak_broken':
        return streakBroken;
      case 'match_proposed':
        return matchProposed;
      case 'match_confirmed':
        return matchConfirmed;
      case 'match_declined':
        return matchDeclined;
      case 'match_found':
        return matchConfirmed;
      default:
        return true;
    }
  }

  NotificationPreferences copyWith({
    bool? newMessage,
    bool? checkinNudge,
    bool? streakBroken,
    bool? matchProposed,
    bool? matchConfirmed,
    bool? matchDeclined,
    bool? matchFound,
  }) {
    return NotificationPreferences(
      newMessage: newMessage ?? this.newMessage,
      checkinNudge: checkinNudge ?? this.checkinNudge,
      streakBroken: streakBroken ?? this.streakBroken,
      matchProposed: matchProposed ?? this.matchProposed,
      matchConfirmed: matchConfirmed ?? matchFound ?? this.matchConfirmed,
      matchDeclined: matchDeclined ?? this.matchDeclined,
    );
  }
}

/// Riverpod notifier managing local notification preferences backed by [SharedPreferences].
class NotificationPreferencesNotifier extends Notifier<NotificationPreferences> {
  static const String keyNewMessage = 'notif_pref_new_message';
  static const String keyCheckinNudge = 'notif_pref_checkin_nudge';
  static const String keyStreakBroken = 'notif_pref_streak_broken';
  static const String keyMatchProposed = 'notif_pref_match_proposed';
  static const String keyMatchConfirmed = 'notif_pref_match_confirmed';
  static const String keyMatchDeclined = 'notif_pref_match_declined';
  static const String keyMatchFound = 'notif_pref_match_found';

  @override
  NotificationPreferences build() {
    _loadFromPreferences();
    return const NotificationPreferences();
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyMatchFound = prefs.getBool(keyMatchFound) ?? true;
      state = NotificationPreferences(
        newMessage: prefs.getBool(keyNewMessage) ?? true,
        checkinNudge: prefs.getBool(keyCheckinNudge) ?? true,
        streakBroken: prefs.getBool(keyStreakBroken) ?? true,
        matchProposed: prefs.getBool(keyMatchProposed) ?? true,
        matchConfirmed: prefs.getBool(keyMatchConfirmed) ?? legacyMatchFound,
        matchDeclined: prefs.getBool(keyMatchDeclined) ?? true,
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

  Future<void> toggleMatchProposed(bool value) async {
    state = state.copyWith(matchProposed: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyMatchProposed, value);
    } catch (_) {}
  }

  Future<void> toggleMatchConfirmed(bool value) async {
    state = state.copyWith(matchConfirmed: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyMatchConfirmed, value);
    } catch (_) {}
  }

  Future<void> toggleMatchDeclined(bool value) async {
    state = state.copyWith(matchDeclined: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyMatchDeclined, value);
    } catch (_) {}
  }

  Future<void> toggleMatchFound(bool value) async {
    await toggleMatchConfirmed(value);
  }
}

/// Provider for notification preferences.
final notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
  NotificationPreferencesNotifier.new,
);
