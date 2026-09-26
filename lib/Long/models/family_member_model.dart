import 'user_model.dart';

enum Role { owner, member }

class FamilyMemberModel {
  final String familyId;
  final UserModel user;
  final Role role;
  DateTime? lastCheckInAt;

  FamilyMemberModel({
    required this.familyId,
    required this.user,
    required this.role,
    this.lastCheckInAt,
  });

  bool get isCheckedInToday {
    if (lastCheckInAt == null) return false;
    final now = DateTime.now();
    return lastCheckInAt!.year == now.year &&
        lastCheckInAt!.month == now.month &&
        lastCheckInAt!.day == now.day;
  }
}
