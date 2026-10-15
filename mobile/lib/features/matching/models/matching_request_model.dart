class MatchingRequestModel {
  final String id;
  final String userId;
  final String goalId;
  final String status;
  final int timezoneToleranceHours;
  final String language;
  final String? podId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MatchingRequestModel({
    required this.id,
    required this.userId,
    required this.goalId,
    required this.status,
    required this.timezoneToleranceHours,
    required this.language,
    this.podId,
    this.createdAt,
    this.updatedAt,
  });

  bool get isMatched => status == 'matched' && podId != null && podId!.isNotEmpty;
  bool get isOpen => status == 'open';
  bool get isCancelled => status == 'cancelled';
  bool get isExpired => status == 'expired';

  factory MatchingRequestModel.fromJson(Map<String, dynamic> json) {
    return MatchingRequestModel(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      goalId: json['goal_id'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      timezoneToleranceHours: json['timezone_tolerance_hours'] as int? ?? 0,
      language: json['language'] as String? ?? 'en',
      podId: json['pod_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'goal_id': goalId,
      'status': status,
      'timezone_tolerance_hours': timezoneToleranceHours,
      'language': language,
      if (podId != null) 'pod_id': podId,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
