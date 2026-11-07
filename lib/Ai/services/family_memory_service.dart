import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/family_memory_model.dart';

/// Dịch vụ quản lý bộ nhớ thói quen & sở thích của gia đình trên Firestore (AC2)
/// Hỗ trợ cả Firestore thời gian thực và In-Memory cache cho hiệu năng và kiểm thử.
class FamilyMemoryService {
  FamilyMemoryService._();
  static final FamilyMemoryService instance = FamilyMemoryService._();

  // In-memory cache: familyId -> {keyword: preference}
  final Map<String, Map<String, String>> _memories = {};

  bool get _isFirebaseAvailable {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore? get _firestore {
    if (!_isFirebaseAvailable) return null;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  CollectionReference<Map<String, dynamic>>? get _collection =>
      _firestore?.collection('family_memories');

  /// Lấy toàn bộ danh sách thói quen đã ghi nhớ của gia đình
  Future<List<FamilyMemory>> getMemories(String familyId) async {
    if (familyId.isEmpty) return [];
    final col = _collection;
    if (col != null) {
      try {
        final snap = await col
            .where('familyId', isEqualTo: familyId)
            .get();

        final list = snap.docs.map((doc) => FamilyMemory.fromFirestore(doc)).toList();
        for (final m in list) {
          _memories.putIfAbsent(familyId, () => {});
          _memories[familyId]![m.keyword] = m.value;
        }
        return list;
      } catch (_) {}
    }

    // Fallback in-memory
    final famMem = _memories[familyId] ?? {};
    return famMem.entries
        .map((e) => FamilyMemory(
              id: '${familyId}_${e.key}',
              familyId: familyId,
              keyword: e.key,
              value: e.value,
              updatedAt: DateTime.now(),
            ))
        .toList();
  }

  /// Lưu hoặc cập nhật thói quen gia đình (Idempotent theo keyword)
  Future<void> savePreference({
    required String familyId,
    required String keyword,
    String? value,
    String? preference,
    String category = 'general',
  }) async {
    final cleanKeyword = keyword.trim().toLowerCase();
    final cleanValue = (value ?? preference ?? '').trim();
    if (familyId.isEmpty || cleanKeyword.isEmpty || cleanValue.isEmpty) return;

    // 1. Cập nhật In-Memory Cache
    _memories.putIfAbsent(familyId, () => {});
    _memories[familyId]![cleanKeyword] = cleanValue;

    // 2. Đồng bộ Firestore nếu có
    final col = _collection;
    if (col != null) {
      try {
        final docId = '${familyId}_$cleanKeyword'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        await col.doc(docId).set({
          'familyId': familyId,
          'keyword': cleanKeyword,
          'value': cleanValue,
          'category': category,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Tra cứu sở thích theo từ khóa đồng bộ
  String? getPreference({
    required String familyId,
    required String keyword,
  }) {
    final sanitizedKey = keyword.trim().toLowerCase();
    final familyMap = _memories[familyId];
    if (familyMap == null) return null;

    if (familyMap.containsKey(sanitizedKey)) {
      return familyMap[sanitizedKey];
    }

    for (final entry in familyMap.entries) {
      if (sanitizedKey.contains(entry.key) || entry.key.contains(sanitizedKey)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Tìm kiếm giá trị thói quen theo từ khóa hoặc câu văn (Async)
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

  /// Lấy toàn bộ danh sách thói quen đã lưu của gia đình
  Map<String, String> getAllPreferences(String familyId) {
    return Map.unmodifiable(_memories[familyId] ?? {});
  }

  /// Xóa bộ nhớ của một gia đình (phục vụ test hoặc làm mới thói quen)
  void clearMemory(String familyId) {
    _memories.remove(familyId);
  }

  /// Xóa toàn bộ bộ nhớ trong app
  void clearAll() {
    _memories.clear();
  }
}
