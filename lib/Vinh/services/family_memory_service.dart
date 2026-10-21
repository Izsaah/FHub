import 'dart:async';

/// Dịch vụ quản lý Bộ nhớ Thói quen Gia đình (Personalization Memory).
/// Lưu trữ các cặp từ khóa - sở thích (VD: sữa -> Vinamilk, bánh mì -> Hoa Sen)
/// theo đúng đặc tả Module 7 của EPIC.
class FamilyMemoryService {
  FamilyMemoryService._();
  static final FamilyMemoryService instance = FamilyMemoryService._();

  // Bộ nhớ đệm lưu trữ theo familyId -> {keyword: preference}
  final Map<String, Map<String, String>> _memories = {};

  /// Lưu một sở thích/thói quen của gia đình
  Future<void> savePreference({
    required String familyId,
    required String keyword,
    required String preference,
  }) async {
    final sanitizedKey = keyword.trim().toLowerCase();
    final sanitizedPref = preference.trim();

    _memories.putIfAbsent(familyId, () => {});
    _memories[familyId]![sanitizedKey] = sanitizedPref;
  }

  /// Tra cứu sở thích theo từ khóa (VD: 'sữa' -> 'Vinamilk')
  String? getPreference({
    required String familyId,
    required String keyword,
  }) {
    final sanitizedKey = keyword.trim().toLowerCase();
    final familyMap = _memories[familyId];
    if (familyMap == null) return null;

    // Tìm kiếm chính xác
    if (familyMap.containsKey(sanitizedKey)) {
      return familyMap[sanitizedKey];
    }

    // Tìm kiếm tương đối nếu từ khóa nằm trong chuỗi
    for (final entry in familyMap.entries) {
      if (sanitizedKey.contains(entry.key) || entry.key.contains(sanitizedKey)) {
        return entry.value;
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
