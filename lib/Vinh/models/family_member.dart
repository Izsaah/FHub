class FamilyMember {
  static const roleGrandparent = 'GRANDPARENT';
  static const roleParent = 'PARENT';
  static const roleChild = 'CHILD';
  static const roleOwner = 'OWNER';
  static const roleRelative = 'RELATIVE';

  final String id;
  final String name;
  final String role;
  final String? hierarchyRole;
  final String? avatarType;
  final String familyId;
  final int rewardStarsTotal;

  const FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    this.hierarchyRole,
    this.avatarType,
    required this.familyId,
    this.rewardStarsTotal = 0,
  });

  String get _effectiveRole =>
      ((hierarchyRole != null && hierarchyRole!.isNotEmpty)
              ? hierarchyRole!
              : role)
          .trim()
          .toUpperCase();

  bool get isOwner =>
      _effectiveRole == roleOwner || _effectiveRole.contains('OWNER');

  bool get isRelative =>
      _effectiveRole == roleRelative ||
      _effectiveRole.contains('RELATIVE') ||
      _effectiveRole.contains('UNCLE') ||
      _effectiveRole.contains('AUNT');

  bool get isParent =>
      !isRelative &&
      (_effectiveRole.contains('PARENT') ||
          _effectiveRole.contains('OWNER') ||
          _effectiveRole.contains('DAD') ||
          _effectiveRole.contains('MOM'));

  bool get isChild =>
      !isRelative &&
      (_effectiveRole.contains('CHILD') ||
          _effectiveRole.contains('CON') ||
          _effectiveRole.contains('KID'));

  bool get isGrandparent =>
      !isRelative &&
      (_effectiveRole.contains('GRANDPARENT') ||
          _effectiveRole.contains('ONG') ||
          _effectiveRole.contains('BA'));

  bool get isGuardian => (isParent || isGrandparent || isOwner) && !isRelative;

  bool get canCreateForOthers => isParent || isGrandparent || isRelative;
  bool get canAssignChores => (isParent || isGrandparent) && !isRelative;

  int get hierarchyLevel {
    if (isGrandparent) return 3;
    if (isParent || isOwner) return 2;
    if (isRelative) return 2;
    return 1;
  }

  String get roleDisplayName {
    if (isGrandparent) return 'Ông Bà';
    if (isParent) return 'Bố Mẹ';
    if (isRelative) return 'Cô / Dì / Chú / Bác';
    if (isChild) return 'Con cái';
    return role;
  }

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: (json['user_id'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? 'Member',
      role: json['role'] as String? ?? 'Member',
      hierarchyRole: (json['hierarchy_role'] ?? json['hierarchyRole']) as String?,
      avatarType: (json['avatar_type'] ?? json['avatarType']) as String?,
      familyId: (json['family_id'] ?? json['familyId'] ?? '').toString(),
      rewardStarsTotal: json['reward_stars_total'] as int? ??
          json['rewardStarsTotal'] as int? ??
          0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'hierarchyRole': hierarchyRole,
      'avatarType': avatarType,
      'familyId': familyId,
      'rewardStarsTotal': rewardStarsTotal,
    };
  }

  FamilyMember copyWith({
    String? id,
    String? name,
    String? role,
    String? hierarchyRole,
    String? avatarType,
    String? familyId,
    int? rewardStarsTotal,
  }) {
    return FamilyMember(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      hierarchyRole: hierarchyRole ?? this.hierarchyRole,
      avatarType: avatarType ?? this.avatarType,
      familyId: familyId ?? this.familyId,
      rewardStarsTotal: rewardStarsTotal ?? this.rewardStarsTotal,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyMember &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}


/// Đại diện cho một Gia đình mà người dùng tham gia (Hỗ trợ 1 người tham gia N gia đình)
class FamilyOption {
  final String id;
  final String name;
  final String? joinCode;
  final String? role;

  const FamilyOption({
    required this.id,
    required this.name,
    this.joinCode,
    this.role,
  });

  /// Sắp xếp danh sách gia đình theo thứ tự bảng chữ cái (A -> Z)
  static List<FamilyOption> sortAlphabetically(Iterable<FamilyOption> items) {
    final list = List<FamilyOption>.from(items);
    list.sort(
      (a, b) =>
          a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase()),
    );
    return list;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyOption &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
