/// Goal domain model representing an accountability goal.
class GoalModel {
  final String id;
  final String userId;
  final String category;
  final String title;
  final String targetDescription;
  final String pace;
  final String? createdAt;
  final String? updatedAt;

  const GoalModel({
    required this.id,
    required this.userId,
    required this.category,
    required this.title,
    required this.targetDescription,
    required this.pace,
    this.createdAt,
    this.updatedAt,
  });

  factory GoalModel.fromJson(Map<String, dynamic> json) {
    return GoalModel(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      category: json['category'] as String? ?? '',
      title: json['title'] as String? ?? '',
      targetDescription: json['target_description'] as String? ?? '',
      pace: json['pace'] as String? ?? 'steady',
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'category': category,
      'title': title,
      'target_description': targetDescription,
      'pace': pace,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
