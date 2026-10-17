enum ReminderTimeSlot {
  slot8AM, // 08:00 - Nhắc nhẹ trên máy Ông Bà
  slot2PM, // 14:00 - Quá 6h: Nhắc rung trên máy Ông Bà
  slot8PM; // 20:00 - Quá 12h: Cảnh báo rung trên máy Bố Mẹ

  String get label {
    switch (this) {
      case ReminderTimeSlot.slot8AM:
        return '08:00 (Nhắc nhẹ)';
      case ReminderTimeSlot.slot2PM:
        return '14:00 (+6h Rung)';
      case ReminderTimeSlot.slot8PM:
        return '20:00 (+12h Cảnh báo Bố Mẹ)';
    }
  }
}

class CheckInReminderItem {
  final String id;
  final String familyId;
  final String targetMemberId;
  final String targetMemberName;
  final String recipientMemberId;
  final String recipientMemberName;
  final ReminderTimeSlot slot;
  final String message;
  final bool isVibration;
  bool isTriggered;
  bool isCancelled;
  final DateTime scheduledTime;

  CheckInReminderItem({
    required this.id,
    required this.familyId,
    required this.targetMemberId,
    required this.targetMemberName,
    required this.recipientMemberId,
    required this.recipientMemberName,
    required this.slot,
    required this.message,
    required this.isVibration,
    this.isTriggered = false,
    this.isCancelled = false,
    required this.scheduledTime,
  });
}
