import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyMember {
  static const roleGrandparent = 'GRANDPARENT';
  static const roleParent = 'PARENT';
  static const roleChild = 'CHILD';

  static const statusActive = 'ACTIVE';
  static const statusDeactivated = 'DEACTIVATED';
  static const statusMemorialized = 'MEMORIALIZED';

  final String familyId;
  final String userId;
  final String role;
  final bool isOwner;
  final String status;
  final DateTime? lastCheckInAt;
  final DateTime? lastCheckInDate;
  final DateTime? lastActiveAt;
  final DateTime? joinedAt;

  const FamilyMember({
    required this.familyId,
    required this.userId,
    required this.role,
    this.isOwner = false,
    this.status = statusActive,
    this.lastCheckInAt,
    this.lastCheckInDate,
    this.lastActiveAt,
    this.joinedAt,
  });

  bool get isActive => status == statusActive;

  factory FamilyMember.fromMap(Map<String, dynamic> map) => FamilyMember(
        familyId: (map['familyId'] ?? map['family_id'] ?? '') as String,
        userId: (map['userId'] ?? map['user_id'] ?? '') as String,
        role: (map['role'] as String?) ?? roleParent,
        isOwner: (map['isOwner'] ?? map['is_owner'] ?? false) as bool,
        status: (map['status'] as String?) ?? statusActive,
        lastCheckInAt: _dateTimeFrom(map['lastCheckInAt'] ?? map['last_check_in_at']),
        lastCheckInDate: _dateTimeFrom(map['lastCheckInDate'] ?? map['last_check_in_date']),
        lastActiveAt: _dateTimeFrom(map['lastActiveAt'] ?? map['last_active_at']),
        joinedAt: _dateTimeFrom(map['joinedAt'] ?? map['joined_at']),
      );

  Map<String, dynamic> toMap() => {
        'familyId': familyId,
        'userId': userId,
        'role': role,
        'isOwner': isOwner,
        'status': status,
        'lastCheckInAt': lastCheckInAt == null ? null : Timestamp.fromDate(lastCheckInAt!),
        'lastCheckInDate': lastCheckInDate == null ? null : Timestamp.fromDate(lastCheckInDate!),
        'lastActiveAt': lastActiveAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(lastActiveAt!),
        'joinedAt': joinedAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(joinedAt!),
      };

  static DateTime? _dateTimeFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
