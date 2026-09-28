class FamilyMember {
  final String familyId;
  final String userId;
  final String role;
  final DateTime? lastCheckInAt;
  final DateTime? lastCheckInDate;

  const FamilyMember({
    required this.familyId,
    required this.userId,
    required this.role,
    this.lastCheckInAt,
    this.lastCheckInDate,
  });

  factory FamilyMember.fromMap(Map<String, dynamic> map) {
    return FamilyMember(
      familyId: map['family_id'] as String,
      userId: map['user_id'] as String,
      role: map['role'] as String? ?? 'MEMBER',
      lastCheckInAt: map['last_check_in_at'] != null
          ? DateTime.tryParse(map['last_check_in_at'].toString())
          : null,
      lastCheckInDate: map['last_check_in_date'] != null
          ? DateTime.tryParse(map['last_check_in_date'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'family_id': familyId,
      'user_id': userId,
      'role': role,
      'last_check_in_at': lastCheckInAt?.toIso8601String(),
      'last_check_in_date': lastCheckInDate?.toIso8601String(),
    };
  }
}
