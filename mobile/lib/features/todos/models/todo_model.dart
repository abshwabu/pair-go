class TodoModel {
  final String id;
  final String podId;
  final String createdBy;
  final String? assignedTo;
  final String title;
  final String? notes;
  final String? dueDate;
  final bool isDone;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TodoModel({
    required this.id,
    required this.podId,
    required this.createdBy,
    this.assignedTo,
    required this.title,
    this.notes,
    this.dueDate,
    this.isDone = false,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory TodoModel.fromJson(Map<String, dynamic> json) {
    return TodoModel(
      id: json['id'] as String? ?? '',
      podId: json['pod_id'] as String? ?? '',
      createdBy: json['created_by'] as String? ?? '',
      assignedTo: json['assigned_to'] as String?,
      title: json['title'] as String? ?? '',
      notes: json['notes'] as String?,
      dueDate: json['due_date'] as String?,
      isDone: json['is_done'] == true || json['is_done'] == 1,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
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
      'pod_id': podId,
      'created_by': createdBy,
      if (assignedTo != null) 'assigned_to': assignedTo,
      'title': title,
      if (notes != null) 'notes': notes,
      if (dueDate != null) 'due_date': dueDate,
      'is_done': isDone,
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
