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
