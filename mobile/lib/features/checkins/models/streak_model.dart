import 'package:flutter/foundation.dart';

/// Represents streak metrics and current day check-in progress for a pod.
@immutable
class PodStreakDetails {
  final int currentStreak;
  final int bestStreak;
  final String? lastCheckInDate;
  final bool meCheckedInToday;
  final bool partnerCheckedInToday;
  final bool bothCheckedInToday;

  const PodStreakDetails({
    required this.currentStreak,
    required this.bestStreak,
    this.lastCheckInDate,
    required this.meCheckedInToday,
    required this.partnerCheckedInToday,
    required this.bothCheckedInToday,
  });

  /// A streak is considered broken when current_streak is 0 but best_streak > 0.
  bool get isStreakBroken => currentStreak == 0 && bestStreak > 0;

  factory PodStreakDetails.fromJson(Map<String, dynamic> json) {
    return PodStreakDetails(
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      lastCheckInDate: json['last_check_in_date'] as String?,
      meCheckedInToday: json['me_checked_in_today'] as bool? ?? false,
      partnerCheckedInToday: json['partner_checked_in_today'] as bool? ?? false,
      bothCheckedInToday: json['both_checked_in_today'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_streak': currentStreak,
      'best_streak': bestStreak,
      'last_check_in_date': lastCheckInDate,
      'me_checked_in_today': meCheckedInToday,
      'partner_checked_in_today': partnerCheckedInToday,
      'both_checked_in_today': bothCheckedInToday,
    };
  }

  PodStreakDetails copyWith({
    int? currentStreak,
    int? bestStreak,
    String? lastCheckInDate,
    bool? meCheckedInToday,
    bool? partnerCheckedInToday,
    bool? bothCheckedInToday,
  }) {
    return PodStreakDetails(
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      lastCheckInDate: lastCheckInDate ?? this.lastCheckInDate,
      meCheckedInToday: meCheckedInToday ?? this.meCheckedInToday,
      partnerCheckedInToday:
          partnerCheckedInToday ?? this.partnerCheckedInToday,
      bothCheckedInToday: bothCheckedInToday ?? this.bothCheckedInToday,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PodStreakDetails &&
          runtimeType == other.runtimeType &&
          currentStreak == other.currentStreak &&
          bestStreak == other.bestStreak &&
          lastCheckInDate == other.lastCheckInDate &&
          meCheckedInToday == other.meCheckedInToday &&
          partnerCheckedInToday == other.partnerCheckedInToday &&
          bothCheckedInToday == other.bothCheckedInToday;

  @override
  int get hashCode => Object.hash(
        currentStreak,
        bestStreak,
        lastCheckInDate,
        meCheckedInToday,
        partnerCheckedInToday,
        bothCheckedInToday,
      );

  @override
  String toString() =>
      'PodStreakDetails(currentStreak: $currentStreak, bestStreak: $bestStreak, lastCheckInDate: $lastCheckInDate, meCheckedInToday: $meCheckedInToday, partnerCheckedInToday: $partnerCheckedInToday, bothCheckedInToday: $bothCheckedInToday)';
}

/// Represents daily check-in participation for a specific UTC date.
@immutable
class DailyCheckInItem {
  final String date;
  final List<String> memberIds;
  final bool bothCheckedIn;

  const DailyCheckInItem({
    required this.date,
    required this.memberIds,
    required this.bothCheckedIn,
  });

  factory DailyCheckInItem.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['member_ids'];
    final members = <String>[];
    if (rawMembers is List) {
      for (final id in rawMembers) {
        if (id != null) {
          members.add(id.toString());
        }
      }
    }

    return DailyCheckInItem(
      date: json['date'] as String? ?? '',
      memberIds: members,
      bothCheckedIn: json['both_checked_in'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'member_ids': memberIds,
      'both_checked_in': bothCheckedIn,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyCheckInItem &&
          runtimeType == other.runtimeType &&
          date == other.date &&
          bothCheckedIn == other.bothCheckedIn &&
          listEquals(memberIds, other.memberIds);

  @override
  int get hashCode => Object.hash(date, bothCheckedIn, Object.hashAll(memberIds));

  @override
  String toString() =>
      'DailyCheckInItem(date: $date, bothCheckedIn: $bothCheckedIn, members: $memberIds)';
}

/// Represents the response returned by POST /api/v1/pods/{pod}/check-ins.
@immutable
class CheckInResult {
  final String id;
  final String podId;
  final String userId;
  final String checkInDate;
  final String? note;
  final int currentStreak;
  final int bestStreak;
  final String? lastCheckInDate;
  final bool checkedInTodayByBoth;
  final DateTime? createdAt;

  const CheckInResult({
    required this.id,
    required this.podId,
    required this.userId,
    required this.checkInDate,
    this.note,
    required this.currentStreak,
    required this.bestStreak,
    this.lastCheckInDate,
    required this.checkedInTodayByBoth,
    this.createdAt,
  });

  factory CheckInResult.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    if (json['created_at'] != null) {
      created = DateTime.tryParse(json['created_at'].toString());
    }

    return CheckInResult(
      id: json['id'] as String? ?? '',
      podId: json['pod_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      checkInDate: json['check_in_date'] as String? ?? '',
      note: json['note'] as String?,
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
      bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      lastCheckInDate: json['last_check_in_date'] as String?,
      checkedInTodayByBoth:
          json['checked_in_today_by_both'] as bool? ?? false,
      createdAt: created,
    );
  }
}
