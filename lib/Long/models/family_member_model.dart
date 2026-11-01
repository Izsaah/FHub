import 'user_model.dart';
import 'hierarchy_role.dart';
import 'member_status.dart';
import '../utils/long_strings.dart';

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

  String get memberRole => hierarchyRole.code;

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

  String get roleLabel {
    switch (hierarchyRole) {
      case HierarchyRole.grandparent:
        return LongStrings.t('Ông / Bà', 'Grandparent');
      case HierarchyRole.child:
        return LongStrings.t('Con cái', 'Child');
      case HierarchyRole.parent:
        return role == Role.owner
            ? LongStrings.t('Chủ nhà', 'Owner')
            : LongStrings.t('Bố / Mẹ', 'Parent');
    }
  }

  factory FamilyMemberModel.fromJson(Map<String, dynamic> json) {
    final rawRole = json['role']?.toString().toUpperCase() ?? 'MEMBER';
    final isOwner =
        (json['isOwner'] ?? json['is_owner']) == true || rawRole == 'OWNER';

    final hierarchyRaw = json['hierarchy_role'] ??
        json['hierarchyRole'] ??
        json['member_role'] ??
        json['memberRole'] ??
        (rawRole != 'OWNER' && rawRole != 'MEMBER' ? rawRole : null);

    final statusRaw = json['status']?.toString();

    final lastActiveRaw = json['last_active_at'] ?? json['lastActiveAt'];
    final lastCheckInRaw = json['last_check_in_at'] ?? json['lastCheckInAt'];
    final lastCheckInDateRaw =
        json['last_check_in_date'] ?? json['lastCheckInDate'];

    return FamilyMemberModel(
      familyId: (json['family_id'] ?? json['familyId'])?.toString() ?? '',
      user: UserModel.fromJson(json['user'] ?? {}),
      role: isOwner ? Role.owner : Role.member,
      hierarchyRole: HierarchyRole.fromString(hierarchyRaw?.toString()),
      status: MemberStatus.fromString(statusRaw),
      lastActiveAt: lastActiveRaw != null
          ? (lastActiveRaw is DateTime
              ? lastActiveRaw
              : DateTime.tryParse(lastActiveRaw.toString()))
          : null,
      lastCheckInAt: lastCheckInRaw != null
          ? (lastCheckInRaw is DateTime
              ? lastCheckInRaw
              : DateTime.tryParse(lastCheckInRaw.toString()))
          : null,
      lastCheckInDate: lastCheckInDateRaw?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'family_id': familyId,
      'user_id': user.id,
      'role': role.name.toUpperCase(),
      'hierarchy_role': hierarchyRole.code,
      'member_role': hierarchyRole.code,
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
