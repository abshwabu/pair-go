class MemberPublicProfile {
  final String id;
  final String name;
  final String? avatarUrl;

  const MemberPublicProfile({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  factory MemberPublicProfile.fromJson(Map<String, dynamic> json) {
    return MemberPublicProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }
}

class MemberGoalInfo {
  final String id;
  final String title;
  final String category;
  final String pace;

  const MemberGoalInfo({
    required this.id,
    required this.title,
    required this.category,
    required this.pace,
  });

  factory MemberGoalInfo.fromJson(Map<String, dynamic> json) {
    return MemberGoalInfo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      pace: json['pace'] as String? ?? 'steady',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'pace': pace,
    };
  }
}

class PodMemberDetail {
  final MemberPublicProfile user;
  final MemberGoalInfo goal;
  final DateTime? joinedAt;
  final DateTime? leftAt;

  const PodMemberDetail({
    required this.user,
    required this.goal,
    this.joinedAt,
    this.leftAt,
  });

  bool get isActive => leftAt == null;

  factory PodMemberDetail.fromJson(Map<String, dynamic> json) {
    return PodMemberDetail(
      user: MemberPublicProfile.fromJson(
        json['user'] as Map<String, dynamic>? ?? {},
      ),
      goal: MemberGoalInfo.fromJson(
        json['goal'] as Map<String, dynamic>? ?? {},
      ),
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'] as String)
          : null,
      leftAt: json['left_at'] != null
          ? DateTime.tryParse(json['left_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'goal': goal.toJson(),
      if (joinedAt != null) 'joined_at': joinedAt!.toIso8601String(),
      if (leftAt != null) 'left_at': leftAt!.toIso8601String(),
    };
  }
}

class StreakSummary {
  final int currentStreak;
  final int bestStreak;
  final String? lastCheckInDate;

  const StreakSummary({
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastCheckInDate,
  });

  factory StreakSummary.fromJson(Map<String, dynamic> json) {
    return StreakSummary(
      currentStreak: json['current_streak'] as int? ?? 0,
      bestStreak: json['best_streak'] as int? ?? 0,
      lastCheckInDate: json['last_check_in_date'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_streak': currentStreak,
      'best_streak': bestStreak,
      if (lastCheckInDate != null) 'last_check_in_date': lastCheckInDate,
    };
  }
}

class PodDetail {
  final String id;
  final String goalCategory;
  final String status;
  final int capacity;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<PodMemberDetail> members;
  final StreakSummary streak;

  const PodDetail({
    required this.id,
    required this.goalCategory,
    required this.status,
    required this.capacity,
    this.createdAt,
    this.updatedAt,
    required this.members,
    required this.streak,
  });

  factory PodDetail.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? [];
    return PodDetail(
      id: json['id'] as String? ?? '',
      goalCategory: json['goal_category'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      capacity: json['capacity'] as int? ?? 2,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      members: rawMembers
          .map((m) => PodMemberDetail.fromJson(m as Map<String, dynamic>))
          .toList(),
      streak: StreakSummary.fromJson(
        json['streak'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'goal_category': goalCategory,
      'status': status,
      'capacity': capacity,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      'members': members.map((m) => m.toJson()).toList(),
      'streak': streak.toJson(),
    };
  }

  PodMemberDetail? partner(String? currentUserId) {
    if (members.isEmpty) return null;
    if (currentUserId == null || currentUserId.isEmpty) {
      return members.length > 1 ? members[1] : members.first;
    }
    for (final member in members) {
      if (member.user.id != currentUserId) {
        return member;
      }
    }
    return members.first;
  }

  PodMemberDetail? myMembership(String? currentUserId) {
    if (members.isEmpty) return null;
    if (currentUserId == null || currentUserId.isEmpty) return members.first;
    for (final member in members) {
      if (member.user.id == currentUserId) {
        return member;
      }
    }
    return null;
  }
}
