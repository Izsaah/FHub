enum ReminderStatus { pending, completed, deleted }

class ReminderModel {
  final String id;
  final String familyId;
  final String creatorId;
  final String assignedTo;
  final String title;
  final DateTime date;
  ReminderStatus status;
  DateTime? completedAt;

  ReminderModel({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.assignedTo,
    required this.title,
    required this.date,
    this.status = ReminderStatus.pending,
    this.completedAt,
  });

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    ReminderStatus parsedStatus = ReminderStatus.pending;
    if (json['status']?.toString().toUpperCase() == 'COMPLETED') parsedStatus = ReminderStatus.completed;
    if (json['status']?.toString().toUpperCase() == 'DELETED') parsedStatus = ReminderStatus.deleted;

    DateTime? parsedDate;
    if (json['date'] != null && json['time'] != null) {
      parsedDate = DateTime.tryParse('${json['date']}T${json['time']}');
    }

    return ReminderModel(
      id: json['id']?.toString() ?? '',
      familyId: json['family_id']?.toString() ?? '',
      creatorId: json['creator_id']?.toString() ?? '',
      assignedTo: json['assigned_to']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      date: parsedDate ?? DateTime.now(),
      status: parsedStatus,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'family_id': familyId,
      'creator_id': creatorId,
      'assigned_to': assignedTo,
      'title': title,
      'date': "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}",
      'time': "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:00",
      'status': status.name.toUpperCase(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }
}
