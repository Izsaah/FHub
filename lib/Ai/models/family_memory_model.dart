import 'package:cloud_firestore/cloud_firestore.dart';

/// Đại diện cho một thói quen / sở thích được AI ghi nhớ trong gia đình (Case 2 - Personalization Memory)
class FamilyMemory {
  final String id;
  final String familyId;
  final String keyword;
  final String value;
  final String category;
  final DateTime updatedAt;

  const FamilyMemory({
    required this.id,
    required this.familyId,
    required this.keyword,
    required this.value,
    this.category = 'general',
    required this.updatedAt,
  });

  factory FamilyMemory.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return FamilyMemory(
      id: doc.id,
      familyId: data['familyId']?.toString() ?? '',
      keyword: data['keyword']?.toString() ?? '',
      value: data['value']?.toString() ?? '',
      category: data['category']?.toString() ?? 'general',
      updatedAt: (data['updatedAt'] is Timestamp)
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'familyId': familyId,
      'keyword': keyword.trim().toLowerCase(),
      'value': value.trim(),
      'category': category,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
