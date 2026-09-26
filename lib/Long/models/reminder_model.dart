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
}
