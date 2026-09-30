class FamilyMember {
  final String id;
  final String name;
  final String role;
  final String? avatarType;
  final String familyId;

  const FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    this.avatarType,
    required this.familyId,
  });

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: (json['user_id'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String? ?? 'Member',
      role: json['role'] as String? ?? 'Member',
      avatarType: (json['avatar_type'] ?? json['avatarType']) as String?,
      familyId: (json['family_id'] ?? json['familyId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'avatarType': avatarType,
      'familyId': familyId,
    };
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
