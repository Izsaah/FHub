import 'package:cloud_firestore/cloud_firestore.dart';

/// 5 Trạng thái truy cập của Gia đình theo kiến trúc SaaS FHub
enum FamilyAccessMode {
  fullPremium,        // Đang trong hạn VIP chính thức
  gracePeriodWarning, // Quá hạn nhưng trong 7 ngày ân hạn (Full tính năng + Banner đếm ngược)
  freeStandard,       // Gói Free chuẩn (Số thành viên Active <= 4)
  overCapacityFrozen, // Gói Free nhưng số thành viên Active > 4 (Khóa tạo mới)
  readOnlyFrozen,     // Gia đình phụ thứ 2, 3 bị đóng băng chỉ đọc khi hết hạn VIP
}

/// Model lưu trạng thái gói cước gắn với Gia đình (Family)
class FamilySubscriptionModel {
  final String familyId;
  final String ownerId;
  final bool isPremium;
  final bool isPrimary;
  final String planName;
  final int maxMembers;
  final int activeMemberCount;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? premiumGraceEndsAt;

  FamilySubscriptionModel({
    required this.familyId,
    this.ownerId = '',
    required this.isPremium,
    this.isPrimary = true,
    required this.planName,
    required this.maxMembers,
    this.activeMemberCount = 1,
    this.startDate,
    this.endDate,
    this.premiumGraceEndsAt,
  });

  /// Thuật toán xác định quyền truy cập gia đình theo mốc thời gian thực
  FamilyAccessMode resolveAccessMode(DateTime trustedNow) {
    if (isPremium && endDate != null && endDate!.isAfter(trustedNow)) {
      return FamilyAccessMode.fullPremium;
    }

    final graceEnd = premiumGraceEndsAt ?? endDate?.add(const Duration(days: 7));
    if (isPremium && graceEnd != null && graceEnd.isAfter(trustedNow)) {
      return FamilyAccessMode.gracePeriodWarning;
    }

    if (isPrimary) {
      if (activeMemberCount > 4) {
        return FamilyAccessMode.overCapacityFrozen;
      }
      return FamilyAccessMode.freeStandard;
    }

    return FamilyAccessMode.readOnlyFrozen;
  }

  /// Tính số ngày ân hạn còn lại (Làm tròn lên chuẩn xác theo giờ)
  int graceDaysRemaining(DateTime trustedNow) {
    if (endDate == null || endDate!.isAfter(trustedNow)) return 0;
    final graceEnd = premiumGraceEndsAt ?? endDate!.add(const Duration(days: 7));
    if (!graceEnd.isAfter(trustedNow)) return 0;

    final remainingHours = graceEnd.difference(trustedNow).inHours;
    return (remainingHours / 24).ceil();
  }

  bool isOverCapacityFrozen(DateTime trustedNow) =>
      resolveAccessMode(trustedNow) == FamilyAccessMode.overCapacityFrozen;

  bool isGracePeriod(DateTime trustedNow) =>
      resolveAccessMode(trustedNow) == FamilyAccessMode.gracePeriodWarning;

  String get formattedExpiry {
    if (endDate == null) return 'Không giới hạn';
    return '${endDate!.day.toString().padLeft(2, '0')}/${endDate!.month.toString().padLeft(2, '0')}/${endDate!.year}';
  }

  static FamilySubscriptionModel freeDefault(String familyId, {String ownerId = ''}) {
    return FamilySubscriptionModel(
      familyId: familyId,
      ownerId: ownerId,
      isPremium: false,
      isPrimary: true,
      planName: 'Gói Cơ Bản (Free)',
      maxMembers: 4,
      activeMemberCount: 1,
    );
  }

  factory FamilySubscriptionModel.fromMap(String familyId, Map<String, dynamic> map) {
    final parsedStart = _parseDateTime(map['subscriptionStartDate'] ?? map['startDate']);
    final parsedEnd = _parseDateTime(map['subscriptionEndDate'] ?? map['endDate']);
    final parsedGrace = _parseDateTime(map['premiumGraceEndsAt'] ?? map['graceEndsAt']);

    return FamilySubscriptionModel(
      familyId: familyId,
      ownerId: map['ownerId'] as String? ?? '',
      isPremium: map['isPremium'] as bool? ?? false,
      isPrimary: map['isPrimary'] as bool? ?? true,
      planName: map['planName'] as String? ?? 'Gói Cơ Bản (Free)',
      maxMembers: map['maxMembers'] as int? ?? 4,
      activeMemberCount: (map['activeMemberCount'] as num?)?.toInt() ?? 1,
      startDate: parsedStart,
      endDate: parsedEnd,
      premiumGraceEndsAt: parsedGrace ?? parsedEnd?.add(const Duration(days: 7)),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'ownerId': ownerId,
      'isPremium': isPremium,
      'isPrimary': isPrimary,
      'planName': planName,
      'maxMembers': maxMembers,
      'activeMemberCount': activeMemberCount,
      'subscriptionStartDate': startDate != null ? Timestamp.fromDate(startDate!) : FieldValue.serverTimestamp(),
      'subscriptionEndDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'premiumGraceEndsAt': premiumGraceEndsAt != null ? Timestamp.fromDate(premiumGraceEndsAt!) : (endDate != null ? Timestamp.fromDate(endDate!.add(const Duration(days: 7))) : null),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  FamilySubscriptionModel copyWith({
    String? familyId,
    String? ownerId,
    bool? isPremium,
    bool? isPrimary,
    String? planName,
    int? maxMembers,
    int? activeMemberCount,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? premiumGraceEndsAt,
  }) {
    return FamilySubscriptionModel(
      familyId: familyId ?? this.familyId,
      ownerId: ownerId ?? this.ownerId,
      isPremium: isPremium ?? this.isPremium,
      isPrimary: isPrimary ?? this.isPrimary,
      planName: planName ?? this.planName,
      maxMembers: maxMembers ?? this.maxMembers,
      activeMemberCount: activeMemberCount ?? this.activeMemberCount,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      premiumGraceEndsAt: premiumGraceEndsAt ?? this.premiumGraceEndsAt,
    );
  }
}
