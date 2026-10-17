import 'user_model.dart';
import 'hierarchy_role.dart';
import 'member_status.dart';

enum Role { owner, member }

class FamilyMemberModel {
  final String familyId;
  final UserModel user;
  Role role;
  HierarchyRole hierarchyRole;
  MemberStatus status;
  DateTime? lastActiveAt;
  DateTime? lastCheckInAt;
  String? lastCheckInDate;

  FamilyMemberModel({
    required this.familyId,
    required this.user,
    required this.role,
    this.hierarchyRole = HierarchyRole.parent,
    this.status = MemberStatus.active,
    this.lastActiveAt,
    this.lastCheckInAt,
    this.lastCheckInDate,
  });

  bool get isOwner => role == Role.owner;
  bool get isActive => status == MemberStatus.active;
  bool get isDeactivated => status == MemberStatus.deactivated;
  bool get isMemorialized => status == MemberStatus.memorialized;

  bool get isGrandparent => hierarchyRole == HierarchyRole.grandparent;
  bool get isParent => hierarchyRole == HierarchyRole.parent;
  bool get isChild => hierarchyRole == HierarchyRole.child;

  bool get isCheckedInToday {
    if (!isActive) return false;
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
      role: json['role']?.toString().toUpperCase() == 'OWNER'
          ? Role.owner
          : Role.member,
      hierarchyRole: HierarchyRole.fromString(json['hierarchy_role']?.toString()),
      status: MemberStatus.fromString(json['status']?.toString()),
      lastActiveAt: json['last_active_at'] != null
          ? DateTime.tryParse(json['last_active_at'].toString())
          : null,
      lastCheckInAt: json['last_check_in_at'] != null
          ? DateTime.tryParse(json['last_check_in_at'].toString())
          : null,
      lastCheckInDate: json['last_check_in_date']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'family_id': familyId,
      'user_id': user.id,
      'role': role.name.toUpperCase(),
      'hierarchy_role': hierarchyRole.code,
      'status': status.code,
      'last_active_at': lastActiveAt?.toIso8601String(),
      'last_check_in_at': lastCheckInAt?.toIso8601String(),
      'last_check_in_date': lastCheckInDate ??
          (lastCheckInAt != null
              ? "${lastCheckInAt!.year}-${lastCheckInAt!.month.toString().padLeft(2, '0')}-${lastCheckInAt!.day.toString().padLeft(2, '0')}"
              : null),
    };
  }

  FamilyMemberModel copyWith({
    String? familyId,
    UserModel? user,
    Role? role,
    HierarchyRole? hierarchyRole,
    MemberStatus? status,
    DateTime? lastActiveAt,
    DateTime? lastCheckInAt,
    String? lastCheckInDate,
  }) {
    return FamilyMemberModel(
      familyId: familyId ?? this.familyId,
      user: user ?? this.user,
      role: role ?? this.role,
      hierarchyRole: hierarchyRole ?? this.hierarchyRole,
      status: status ?? this.status,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      lastCheckInAt: lastCheckInAt ?? this.lastCheckInAt,
      lastCheckInDate: lastCheckInDate ?? this.lastCheckInDate,
    );
  }
}
