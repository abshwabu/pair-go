class ChatMessageModel {
  final String id;
  final String podId;
  final String senderId;
  final String? body;
  final String? attachmentUrl;
  final DateTime createdAt;

  const ChatMessageModel({
    required this.id,
    required this.podId,
    required this.senderId,
    this.body,
    this.attachmentUrl,
    required this.createdAt,
  });

  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.trim().isNotEmpty;
  bool get hasBody => body != null && body!.trim().isNotEmpty;

  ChatMessageModel copyWith({
    String? id,
    String? podId,
    String? senderId,
    String? body,
    String? attachmentUrl,
    DateTime? createdAt,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      podId: podId ?? this.podId,
      senderId: senderId ?? this.senderId,
      body: body ?? this.body,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final rawCreated = json['created_at'];
    if (rawCreated is String) {
      parsedDate = DateTime.tryParse(rawCreated)?.toUtc() ?? DateTime.now().toUtc();
    } else {
      parsedDate = DateTime.now().toUtc();
    }

    return ChatMessageModel(
      id: json['id'] as String? ?? '',
      podId: json['pod_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      body: json['body'] as String?,
      attachmentUrl: json['attachment_url'] as String?,
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pod_id': podId,
      'sender_id': senderId,
      if (body != null) 'body': body,
      if (attachmentUrl != null) 'attachment_url': attachmentUrl,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
