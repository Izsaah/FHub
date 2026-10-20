import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/family_memory_model.dart';

/// Dịch vụ quản lý bộ nhớ thói quen & sở thích của gia đình trên Firestore (AC2)
class FamilyMemoryService {
  FamilyMemoryService._();
  static final FamilyMemoryService instance = FamilyMemoryService._();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('family_memories');

  /// Lấy toàn bộ danh sách thói quen đã ghi nhớ của gia đình
  Future<List<FamilyMemory>> getMemories(String familyId) async {
    if (familyId.isEmpty) return [];
    try {
      final snap = await _collection
          .where('familyId', isEqualTo: familyId)
          .get();

      return snap.docs.map((doc) => FamilyMemory.fromFirestore(doc)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Lưu hoặc cập nhật thói quen gia đình (Idempotent theo keyword)
  Future<void> savePreference({
    required String familyId,
    required String keyword,
    required String value,
    String category = 'general',
  }) async {
    final cleanKeyword = keyword.trim().toLowerCase();
    final cleanValue = value.trim();
    if (familyId.isEmpty || cleanKeyword.isEmpty || cleanValue.isEmpty) return;

    final docId = '${familyId}_$cleanKeyword'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');

    await _collection.doc(docId).set({
      'familyId': familyId,
      'keyword': cleanKeyword,
      'value': cleanValue,
      'category': category,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Tìm kiếm giá trị thói quen theo từ khóa hoặc câu văn
  Future<String?> findPreference(String familyId, String text) async {
    final memories = await getMemories(familyId);
    final cleanText = text.toLowerCase();
    for (final mem in memories) {
      if (cleanText.contains(mem.keyword)) {
        return mem.value;
      }
    }
    return null;
  }
}
