/// Represents a blocked user row returned from GET /api/v1/blocks.
class BlockedUserModel {
  final String id;
  final String blockedUserId;
  final String name;
  final String? avatarUrl;
  final DateTime? createdAt;

  const BlockedUserModel({
    required this.id,
    required this.blockedUserId,
    required this.name,
    this.avatarUrl,
    this.createdAt,
  });

  factory BlockedUserModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d is String && d.isNotEmpty) {
        return DateTime.tryParse(d);
      }
      return null;
    }

    return BlockedUserModel(
      id: json['id'] as String? ?? '',
      blockedUserId: json['blocked_user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'User',
      avatarUrl: json['avatar_url'] as String?,
      createdAt: parseDate(json['created_at']),
    );
  }
}
