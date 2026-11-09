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
  bool isKid;
  int rewardStarsTotal;

  FamilyMemberModel({
    required this.familyId,
    required this.user,
    required this.role,
    this.hierarchyRole = HierarchyRole.parent,
    this.status = MemberStatus.active,
    this.lastActiveAt,
    this.lastCheckInAt,
    this.lastCheckInDate,
    bool? isKid,
    this.rewardStarsTotal = 0,
  }) : isKid = isKid ?? (hierarchyRole == HierarchyRole.child);

  String get memberRole => hierarchyRole.code;

  bool get isOwner => role == Role.owner;
  bool get isActive => status == MemberStatus.active;
  bool get isDeactivated => status == MemberStatus.deactivated;
  bool get isMemorialized => status == MemberStatus.memorialized;

  bool get isGrandparent => hierarchyRole == HierarchyRole.grandparent;
  bool get isParent => hierarchyRole == HierarchyRole.parent;
  bool get isChild => hierarchyRole == HierarchyRole.child;
  bool get isRelative => hierarchyRole == HierarchyRole.relative;

  /// Guardian bao gồm: Chủ hộ (Owner), Bố Mẹ (Parent), và Ông Bà (Grandparent)
  bool get isGuardian => isOwner || isParent || isGrandparent;

  int get hierarchyLevel => hierarchyRole.hierarchyLevel;

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
      case HierarchyRole.relative:
        return LongStrings.t('Cô / Dì / Chú / Bác', 'Relative');
      case HierarchyRole.member:
        return LongStrings.t('Bạn bè', 'Friend');
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

    final hierarchyRole = HierarchyRole.fromString(hierarchyRaw?.toString());

    // isKid parsing with safe fallback to child role check
    final rawIsKid = json['isKid'] ?? json['is_kid'];
    final bool? parsedIsKid = rawIsKid != null
        ? (rawIsKid == true || rawIsKid.toString().toLowerCase() == 'true')
        : null;

    // rewardStarsTotal parsing with default 0
    final rawStars = json['rewardStarsTotal'] ??
        json['reward_stars_total'] ??
        json['stars'] ??
        json['rewardStars'];
    final int parsedStars = (rawStars is num)
        ? rawStars.toInt()
        : int.tryParse(rawStars?.toString() ?? '0') ?? 0;

    return FamilyMemberModel(
      familyId: (json['family_id'] ?? json['familyId'])?.toString() ?? '',
      user: UserModel.fromJson(json['user'] ?? {}),
      role: isOwner ? Role.owner : Role.member,
      hierarchyRole: hierarchyRole,
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
      isKid: parsedIsKid,
      rewardStarsTotal: parsedStars,
    );
  }

  factory FamilyMemberModel.fromMap(Map<String, dynamic> map) =>
      FamilyMemberModel.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'family_id': familyId,
      'familyId': familyId,
      'user_id': user.id,
      'userId': user.id,
      'role': role.name.toUpperCase(),
      'hierarchy_role': hierarchyRole.code,
      'hierarchyRole': hierarchyRole.code,
      'member_role': hierarchyRole.code,
      'status': status.code,
      'is_kid': isKid,
      'isKid': isKid,
      'reward_stars_total': rewardStarsTotal,
      'rewardStarsTotal': rewardStarsTotal,
      'last_active_at': lastActiveAt?.toIso8601String(),
      'last_check_in_at': lastCheckInAt?.toIso8601String(),
      'last_check_in_date': lastCheckInDate ??
          (lastCheckInAt != null
              ? "${lastCheckInAt!.year}-${lastCheckInAt!.month.toString().padLeft(2, '0')}-${lastCheckInAt!.day.toString().padLeft(2, '0')}"
              : null),
    };
  }

  Map<String, dynamic> toMap() => toJson();

  FamilyMemberModel copyWith({
    String? familyId,
    UserModel? user,
    Role? role,
    HierarchyRole? hierarchyRole,
    MemberStatus? status,
    DateTime? lastActiveAt,
    DateTime? lastCheckInAt,
    String? lastCheckInDate,
    bool? isKid,
    int? rewardStarsTotal,
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
      isKid: isKid ?? this.isKid,
      rewardStarsTotal: rewardStarsTotal ?? this.rewardStarsTotal,
    );
  }
}
