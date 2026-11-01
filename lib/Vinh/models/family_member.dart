class FamilyMember {
  static const roleGrandparent = 'GRANDPARENT';
  static const roleParent = 'PARENT';
  static const roleChild = 'CHILD';
  static const roleOwner = 'OWNER';

  final String id;
  final String name;
  final String role;
  final String? avatarType;
  final String familyId;
  final int rewardStarsTotal;

  const FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    this.avatarType,
    required this.familyId,
    this.rewardStarsTotal = 0,
  });

  bool get isParent =>
      role.toUpperCase().contains('PARENT') ||
      role.toUpperCase().contains('OWNER') ||
      role.toUpperCase().contains('DAD') ||
      role.toUpperCase().contains('MOM') ||
      name.toLowerCase().contains('bố') ||
      name.toLowerCase().contains('mẹ') ||
      name.toLowerCase().contains('dad') ||
      name.toLowerCase().contains('mom');

  bool get isChild =>
      role.toUpperCase().contains('CHILD') ||
      role.toUpperCase().contains('CON') ||
      id.contains('minh') ||
      name.toLowerCase().contains('minh') ||
      name.toLowerCase().contains('con');

  bool get isGrandparent =>
      role.toUpperCase().contains('GRANDPARENT') ||
      name.toLowerCase().contains('ông') ||
      name.toLowerCase().contains('bà');

  bool get canCreateForOthers => isParent || isGrandparent;
  bool get canAssignChores => isParent || isGrandparent;

  String get roleDisplayName {
    if (isGrandparent) return 'Ông Bà';
    if (isParent) return 'Bố Mẹ';
    if (isChild) return 'Con cái';
    return role;
  }

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: (json['user_id'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? 'Member',
      role: json['role'] as String? ?? 'Member',
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
      'avatarType': avatarType,
      'familyId': familyId,
      'rewardStarsTotal': rewardStarsTotal,
    };
  }

  FamilyMember copyWith({
    String? id,
    String? name,
    String? role,
    String? avatarType,
    String? familyId,
    int? rewardStarsTotal,
  }) {
    return FamilyMember(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
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
