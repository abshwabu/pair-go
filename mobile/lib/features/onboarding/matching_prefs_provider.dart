import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';

class MatchingPrefsState {
  final int timezoneToleranceHours;
  final String language;
  final bool isLoading;
  final String? errorMessage;

  const MatchingPrefsState({
    this.timezoneToleranceHours = 3,
    this.language = 'en',
    this.isLoading = false,
    this.errorMessage,
  });

  MatchingPrefsState copyWith({
    int? timezoneToleranceHours,
    String? language,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return MatchingPrefsState(
      timezoneToleranceHours:
          timezoneToleranceHours ?? this.timezoneToleranceHours,
      language: language ?? this.language,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class MatchingPrefsNotifier extends Notifier<MatchingPrefsState> {
  @override
  MatchingPrefsState build() {
    String defaultLang = 'en';
    try {
      final deviceCode = PlatformDispatcher.instance.locale.languageCode;
      if (deviceCode.isNotEmpty) {
        defaultLang = deviceCode;
      }
    } catch (_) {
      defaultLang = 'en';
    }

    return MatchingPrefsState(language: defaultLang);
  }

  void setTimezoneTolerance(int hours) {
    state = state.copyWith(timezoneToleranceHours: hours);
  }

  void setLanguage(String lang) {
    state = state.copyWith(language: lang);
  }

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  void saveAndProceed(BuildContext context) {
    // Preferences are persisted in the notifier's state for the matching worker
    context.go(AppRoutes.findingMatchPath);
  }
}

final matchingPrefsNotifierProvider =
    NotifierProvider<MatchingPrefsNotifier, MatchingPrefsState>(
  MatchingPrefsNotifier.new,
);
