import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyMember {
  static const roleGrandparent = 'GRANDPARENT';
  static const roleParent = 'PARENT';
  static const roleChild = 'CHILD';
  static const roleRelative = 'RELATIVE';

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
  final bool? _rawIsKid;
  final int rewardStarsTotal;

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
    bool? isKid,
    this.rewardStarsTotal = 0,
  }) : _rawIsKid = isKid;

  bool get isActive => status == statusActive;

  bool get isGrandparent =>
      role.toUpperCase() == roleGrandparent ||
      role.toUpperCase().contains('GRANDPARENT');

  bool get isParent =>
      role.toUpperCase() == roleParent ||
      role.toUpperCase().contains('PARENT') ||
      role.toUpperCase().contains('OWNER');

  bool get isChild =>
      role.toUpperCase() == roleChild ||
      role.toUpperCase().contains('CHILD') ||
      role.toUpperCase().contains('CON');

  bool get isRelative =>
      role == roleRelative ||
      role.toUpperCase() == roleRelative ||
      role.toUpperCase().contains('RELATIVE') ||
      role.toUpperCase().contains('UNCLE') ||
      role.toUpperCase().contains('AUNT');

  /// isKid: mặc định true đối với trẻ nhỏ (isChild), false với người lớn nếu không chỉ định
  bool get isKid => _rawIsKid ?? isChild;

  /// Guardian bao gồm: Chủ hộ (isOwner), Bố Mẹ (isParent), và Ông Bà (isGrandparent)
  bool get isGuardian => (isOwner || isParent || isGrandparent) && !isRelative;

  int get hierarchyLevel {
    if (isGrandparent) return 3;
    if (isParent || isOwner) return 2;
    if (isRelative) return 2;
    return 1;
  }

  factory FamilyMember.fromMap(Map<String, dynamic> map) {
    final rawIsKid = map['isKid'] ?? map['is_kid'];
    final bool? parsedIsKid = rawIsKid != null
        ? (rawIsKid == true || rawIsKid.toString().toLowerCase() == 'true')
        : null;

    final rawStars = map['rewardStarsTotal'] ??
        map['reward_stars_total'] ??
        map['stars'] ??
        map['rewardStars'];
    final int parsedStars = (rawStars is num)
        ? rawStars.toInt()
        : int.tryParse(rawStars?.toString() ?? '0') ?? 0;

    return FamilyMember(
      familyId: (map['familyId'] ?? map['family_id'] ?? '') as String,
      userId: (map['userId'] ?? map['user_id'] ?? '') as String,
      role: (map['role'] as String?) ?? roleParent,
      isOwner: (map['isOwner'] ?? map['is_owner'] ?? false) as bool,
      status: (map['status'] as String?) ?? statusActive,
      lastCheckInAt:
          _dateTimeFrom(map['lastCheckInAt'] ?? map['last_check_in_at']),
      lastCheckInDate:
          _dateTimeFrom(map['lastCheckInDate'] ?? map['last_check_in_date']),
      lastActiveAt:
          _dateTimeFrom(map['lastActiveAt'] ?? map['last_active_at']),
      joinedAt: _dateTimeFrom(map['joinedAt'] ?? map['joined_at']),
      isKid: parsedIsKid,
      rewardStarsTotal: parsedStars,
    );
  }

  factory FamilyMember.fromJson(Map<String, dynamic> json) =>
      FamilyMember.fromMap(json);

  Map<String, dynamic> toMap() => {
        'familyId': familyId,
        'userId': userId,
        'role': role,
        'isOwner': isOwner,
        'status': status,
        'isKid': isKid,
        'is_kid': isKid,
        'rewardStarsTotal': rewardStarsTotal,
        'reward_stars_total': rewardStarsTotal,
        'lastCheckInAt': lastCheckInAt == null
            ? null
            : Timestamp.fromDate(lastCheckInAt!),
        'lastCheckInDate': lastCheckInDate == null
            ? null
            : Timestamp.fromDate(lastCheckInDate!),
        'lastActiveAt': lastActiveAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(lastActiveAt!),
        'joinedAt': joinedAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(joinedAt!),
      };

  Map<String, dynamic> toJson() => toMap();

  FamilyMember copyWith({
    String? familyId,
    String? userId,
    String? role,
    bool? isOwner,
    String? status,
    DateTime? lastCheckInAt,
    DateTime? lastCheckInDate,
    DateTime? lastActiveAt,
    DateTime? joinedAt,
    bool? isKid,
    int? rewardStarsTotal,
  }) {
    return FamilyMember(
      familyId: familyId ?? this.familyId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      isOwner: isOwner ?? this.isOwner,
      status: status ?? this.status,
      lastCheckInAt: lastCheckInAt ?? this.lastCheckInAt,
      lastCheckInDate: lastCheckInDate ?? this.lastCheckInDate,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      joinedAt: joinedAt ?? this.joinedAt,
      isKid: isKid ?? this.isKid,
      rewardStarsTotal: rewardStarsTotal ?? this.rewardStarsTotal,
    );
  }

  static DateTime? _dateTimeFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
