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

  factory FamilyMemberModel.fromJson(Map<String, dynamic> json) {
    return FamilyMemberModel(
      familyId: json['family_id']?.toString() ?? '',
      user: UserModel.fromJson(json['user'] ?? {}),
      role: json['role']?.toString().toUpperCase() == 'OWNER' ? Role.owner : Role.member,
      lastCheckInAt: json['last_check_in_at'] != null ? DateTime.parse(json['last_check_in_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'family_id': familyId,
      'user_id': user.id, // Usually we only send user_id to DB
      'role': role.name.toUpperCase(),
      'last_check_in_at': lastCheckInAt?.toIso8601String(),
      'last_check_in_date': lastCheckInAt != null 
          ? "${lastCheckInAt!.year}-${lastCheckInAt!.month.toString().padLeft(2, '0')}-${lastCheckInAt!.day.toString().padLeft(2, '0')}"
          : null,
    };
  }
}
