import 'dart:convert';

/// Represents an in-app notification loaded from GET /api/v1/notifications.
class InAppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String? podId;
  final DateTime? sentAt;
  final DateTime? readAt;
  final DateTime createdAt;

  const InAppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.podId,
    this.sentAt,
    this.readAt,
    required this.createdAt,
  });

  bool get isRead => readAt != null;

  factory InAppNotification.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> payloadMap = {};
    if (json['payload'] != null) {
      if (json['payload'] is Map<String, dynamic>) {
        payloadMap = json['payload'] as Map<String, dynamic>;
      } else if (json['payload'] is String) {
        try {
          final decoded = jsonDecode(json['payload'] as String);
          if (decoded is Map<String, dynamic>) {
            payloadMap = decoded;
          }
        } catch (_) {}
      }
    }

    final rawType = json['type'] as String? ??
        payloadMap['type'] as String? ??
        'new_message';
    final title = payloadMap['title'] as String? ??
        json['title'] as String? ??
        _defaultTitle(rawType);
    final body = payloadMap['body'] as String? ?? json['body'] as String? ?? '';
    final podId = payloadMap['pod_id'] as String? ?? json['pod_id'] as String?;

    DateTime? parseDate(dynamic d) {
      if (d is String && d.isNotEmpty) {
        return DateTime.tryParse(d);
      }
      return null;
    }

    return InAppNotification(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      type: rawType,
      title: title,
      body: body,
      podId: podId,
      sentAt: parseDate(json['sent_at']),
      readAt: parseDate(json['read_at']),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  static String _defaultTitle(String type) {
    switch (type) {
      case 'new_message':
        return 'New Message';
      case 'checkin_nudge':
        return 'Check-in Nudge';
      case 'streak_broken':
        return 'Streak Broken';
      case 'match_found':
        return 'Partner Matched!';
      default:
        return 'Notification';
    }
  }

  InAppNotification copyWith({
    DateTime? readAt,
  }) {
    return InAppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      podId: podId,
      sentAt: sentAt,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }
}
