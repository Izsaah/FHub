import 'package:cloud_firestore/cloud_firestore.dart';

/// Model lưu trạng thái gói cước gắn với Gia đình (Family)
class FamilySubscriptionModel {
  final String familyId;
  final bool isPremium;
  final String planName;
  final int maxMembers;
  final DateTime? startDate;
  final DateTime? endDate;

  FamilySubscriptionModel({
    required this.familyId,
    required this.isPremium,
    required this.planName,
    required this.maxMembers,
    this.startDate,
    this.endDate,
  });

  String get formattedExpiry {
    if (endDate == null) return 'Không giới hạn';
    return '${endDate!.day.toString().padLeft(2, '0')}/${endDate!.month.toString().padLeft(2, '0')}/${endDate!.year}';
  }

  static FamilySubscriptionModel freeDefault(String familyId) {
    return FamilySubscriptionModel(
      familyId: familyId,
      isPremium: false,
      planName: 'Gói Cơ Bản (Free)',
      maxMembers: 4,
    );
  }

  factory FamilySubscriptionModel.fromMap(String familyId, Map<String, dynamic> map) {
    return FamilySubscriptionModel(
      familyId: familyId,
      isPremium: map['isPremium'] as bool? ?? false,
      planName: map['planName'] as String? ?? 'Gói Cơ Bản (Free)',
      maxMembers: map['maxMembers'] as int? ?? 4,
      startDate: _parseDateTime(map['subscriptionStartDate'] ?? map['startDate']),
      endDate: _parseDateTime(map['subscriptionEndDate'] ?? map['endDate']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isPremium': isPremium,
      'planName': planName,
      'maxMembers': maxMembers,
      'subscriptionStartDate': startDate != null ? Timestamp.fromDate(startDate!) : FieldValue.serverTimestamp(),
      'subscriptionEndDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
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
    bool? isPremium,
    String? planName,
    int? maxMembers,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return FamilySubscriptionModel(
      familyId: familyId ?? this.familyId,
      isPremium: isPremium ?? this.isPremium,
      planName: planName ?? this.planName,
      maxMembers: maxMembers ?? this.maxMembers,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }
}

