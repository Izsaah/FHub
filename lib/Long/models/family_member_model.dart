import 'user_model.dart';
import '../utils/long_strings.dart';

enum Role { owner, member }

class FamilyMemberModel {
  final String familyId;
  final UserModel user;
  final Role role;
  final String memberRole;
  DateTime? lastCheckInAt;

  FamilyMemberModel({
    required this.familyId,
    required this.user,
    required this.role,
    this.memberRole = 'PARENT',
    this.lastCheckInAt,
  });

  bool get isCheckedInToday {
    if (lastCheckInAt == null) return false;
    final now = DateTime.now();
    return lastCheckInAt!.year == now.year &&
        lastCheckInAt!.month == now.month &&
        lastCheckInAt!.day == now.day;
  }

  String get roleLabel {
    switch (memberRole.toUpperCase()) {
      case 'GRANDPARENT':
        return LongStrings.t('Ông / Bà', 'Grandparent');
      case 'CHILD':
        return LongStrings.t('Con cái', 'Child');
      case 'PARENT':
        return LongStrings.t('Bố / Mẹ', 'Parent');
      default:
        return role == Role.owner
            ? LongStrings.t('Chủ nhà', 'Owner')
            : LongStrings.t('Thành viên', 'Member');
    }
  }

  factory FamilyMemberModel.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role']?.toString().toUpperCase() ?? 'MEMBER';
    final isOwner =
        (json['isOwner'] ?? json['is_owner']) == true || rawRole == 'OWNER';
    return FamilyMemberModel(
      familyId: (json['family_id'] ?? json['familyId'])?.toString() ?? '',
      user: UserModel.fromJson(json['user'] ?? {}),
      role: isOwner ? Role.owner : Role.member,
      memberRole: rawRole,
      lastCheckInAt: json['last_check_in_at'] != null
          ? DateTime.tryParse(json['last_check_in_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'family_id': familyId,
      'user_id': user.id,
      'role': role.name.toUpperCase(),
      'member_role': memberRole,
      'last_check_in_at': lastCheckInAt?.toIso8601String(),
      'last_check_in_date': lastCheckInAt != null
          ? "${lastCheckInAt!.year}-${lastCheckInAt!.month.toString().padLeft(2, '0')}-${lastCheckInAt!.day.toString().padLeft(2, '0')}"
          : null,
    };
  }
}
