import 'dart:async';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import 'family_memory_service.dart';
import 'reminder_repository.dart';

/// Tin nhắn trong đoạn hội thoại với Trợ lý AI Gia đình
class AiChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final ReminderModel? attachedReminder;

  const AiChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.attachedReminder,
  });
}

/// Trạng thái chờ làm rõ trong hội thoại đa lượt (Multi-turn clarification)
class PendingClarification {
  final String keyword;
  final String targetAssigneeId;
  final String targetAssigneeName;
  final String action;

  const PendingClarification({
    required this.keyword,
    required this.targetAssigneeId,
    required this.targetAssigneeName,
    required this.action,
  });
}

/// Dịch vụ Trí tuệ AI Gia đình (Module 7 EPIC)
/// - Xử lý NLU tiếng Việt thông minh cho các kịch bản gia đình.
/// - Case 1: Giao việc mở cho các con (Open Task).
/// - Case 2: Cá nhân hóa & Nhớ thói quen (Personalization Memory - Vinamilk).
/// - Case 3: Báo cáo nhanh tiến độ công việc trong ngày.
class FamilyAiAssistantService {
  FamilyAiAssistantService._();
  static final FamilyAiAssistantService instance = FamilyAiAssistantService._();

  final Map<String, PendingClarification> _pendingClarifications = {};

  /// Xóa trạng thái chờ làm rõ
  void reset(String familyId) {
    _pendingClarifications.remove(familyId);
  }

  /// Xử lý tin nhắn của người dùng và sinh phản hồi cùng với Reminder (nếu có)
  Future<AiChatMessage> processMessage({
    required String familyId,
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMember> familyMembers,
    required ReminderRepository repository,
    required String userMessage,
    DateTime? now,
  }) async {
    final query = userMessage.trim();
    final lower = query.toLowerCase();
    final effectiveNow = now ?? DateTime.now();
    final targetDt = effectiveNow.add(const Duration(hours: 2));
    final targetDateStr =
        '${targetDt.day.toString().padLeft(2, '0')}/${targetDt.month.toString().padLeft(2, '0')}/${targetDt.year}';
    final targetTimeStr =
        '${targetDt.hour.toString().padLeft(2, '0')}:${targetDt.minute.toString().padLeft(2, '0')}';
    final todayStr =
        '${effectiveNow.day.toString().padLeft(2, '0')}/${effectiveNow.month.toString().padLeft(2, '0')}/${effectiveNow.year}';

    // 1. KIỂM TRA TRẠNG THÁI HỘI THOẠI ĐA LƯỢT (Case 2: Trả lời chi tiết thói quen)
    final pending = _pendingClarifications[familyId];
    if (pending != null) {
      // Cho phép hủy nếu đổi ý
      if (lower == 'hủy' ||
          lower == 'thôi' ||
          lower.contains('không mua') ||
          lower == 'bỏ qua') {
        _pendingClarifications.remove(familyId);
        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text:
              'Dạ, em đã hủy yêu cầu nhắc mua ${pending.keyword} rồi ạ! Bạn cần em hỗ trợ việc gì khác không nhé? 😊',
          timestamp: DateTime.now(),
        );
      }

      _pendingClarifications.remove(familyId);

      // Trích xuất thương hiệu/sở thích (VD: "Vinamilk", "TH True Milk", v.v.)
      String preference = query;
      if (lower.contains('vinamilk')) {
        preference = 'Vinamilk';
      } else if (lower.contains('th true milk') || lower.contains('th')) {
        preference = 'TH True Milk';
      } else if (lower.contains('dutch lady') || lower.contains('cô gái hà lan')) {
        preference = 'Cô Gái Hà Lan';
      }

      // Lưu vào bộ nhớ gia đình (FamilyMemoryService)
      await FamilyMemoryService.instance.savePreference(
        familyId: familyId,
        keyword: pending.keyword,
        preference: preference,
      );

      // Tạo reminder với chi tiết đã học
      final taskTitle = 'Mua ${pending.keyword} ($preference)';
      final created = await repository.createReminder(
        reminder: ReminderModel(
          id: 'rem_${DateTime.now().millisecondsSinceEpoch}',
          familyId: familyId,
          creatorId: currentUserId,
          creatorName: currentUserName,
          assignedTo: pending.targetAssigneeId,
          assignedToName: pending.targetAssigneeName,
          title: taskTitle,
          date: targetDateStr,
          time: targetTimeStr,
          status: ReminderStatus.pending,
          createdAt: DateTime.now(),
        ),
        currentUserId: currentUserId,
        familyMembers: familyMembers,
      );

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text:
            'Dạ, em đã ghi nhớ thói quen mua ${pending.keyword} "$preference" vào bộ nhớ gia đình và tạo lời nhắc "$taskTitle" cho ${pending.targetAssigneeName} vào lúc $targetTimeStr rồi ạ! 🥛\n\nTừ nay, cả nhà chỉ cần bảo "Nhắc mua ${pending.keyword}" là em tự động điền "$preference" luôn nhé.',
        timestamp: DateTime.now(),
        attachedReminder: created,
      );
    }

    // 2. CASE 1: GIAO VIỆC MỞ CHO CÁC CON (OPEN TASK)
    // VD: "Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?", "cần người dọn nhà", "tìm người phụ việc nhà"
    if (_isOpenTaskIntent(lower)) {
      String choreTitle = 'Phụ mẹ làm việc nhà';
      if (lower.contains('dọn nhà') || lower.contains('dọn dẹp')) {
        choreTitle = 'Dọn dẹp nhà cửa phụ mẹ';
      } else if (lower.contains('nấu cơm') || lower.contains('nấu ăn')) {
        choreTitle = 'Phụ mẹ nấu cơm chiều';
      } else if (lower.contains('rửa chén') || lower.contains('rửa bát')) {
        choreTitle = 'Rửa chén phụ mẹ';
      }

      final created = await repository.createReminder(
        reminder: ReminderModel(
          id: 'rem_${DateTime.now().millisecondsSinceEpoch}_open',
          familyId: familyId,
          creatorId: currentUserId,
          creatorName: currentUserName,
          assignedTo: 'OPEN',
          assignedToName: 'Cả nhà (Việc chung)',
          title: choreTitle,
          date: targetDateStr,
          time: targetTimeStr,
          status: ReminderStatus.open,
          createdAt: DateTime.now(),
        ),
        currentUserId: currentUserId,
        familyMembers: familyMembers,
      );

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text:
            'Dạ mẹ! Em đã tạo một Công việc chung (Open Task) "$choreTitle" cho cả nhà rồi ạ. Các con có thể bấm "Nhận việc ngay" trên thẻ dưới đây để xung phong làm nhé! 👨‍👩‍👧',
        timestamp: DateTime.now(),
        attachedReminder: created,
      );
    }

    // 3. CASE 2: CÁ NHÂN HÓA & NHỚ THÓI QUEN (PERSONALIZATION MEMORY)
    // VD: "Giao mua sữa cho Bố", "Nhắc bố mua sữa", "Nhắc mua sữa"
    if (_isMilkOrGroceryIntent(lower)) {
      final keyword = 'sữa';
      final savedPreference = FamilyMemoryService.instance.getPreference(
        familyId: familyId,
        keyword: keyword,
      );

      // Tìm thông tin Bố trong danh sách thành viên gia đình (đảm bảo luôn tồn tại trong familyMembers)
      FamilyMember dadMember;
      if (familyMembers.isNotEmpty) {
        dadMember = familyMembers.firstWhere(
          (m) =>
              m.name.toLowerCase().contains('dad') ||
              m.name.toLowerCase().contains('bố') ||
              m.name.toLowerCase().contains('ba') ||
              m.name.toLowerCase().contains('cha') ||
              (m.isParent && m.id != currentUserId),
          orElse: () => familyMembers.firstWhere(
            (m) => m.id != currentUserId,
            orElse: () => familyMembers.first,
          ),
        );
      } else {
        dadMember = FamilyMember(
          id: 'user_dad',
          name: 'Dad',
          role: FamilyMember.roleParent,
          familyId: familyId,
        );
      }

      if (savedPreference != null && savedPreference.isNotEmpty) {
        // Đã học được thói quen -> Tự động điền không cần hỏi lại
        final taskTitle = 'Mua sữa ($savedPreference)';
        final created = await repository.createReminder(
          reminder: ReminderModel(
            id: 'rem_${DateTime.now().millisecondsSinceEpoch}',
            familyId: familyId,
            creatorId: currentUserId,
            creatorName: currentUserName,
            assignedTo: dadMember.id,
            assignedToName: dadMember.name,
            title: taskTitle,
            date: targetDateStr,
            time: targetTimeStr,
            status: ReminderStatus.pending,
            createdAt: DateTime.now(),
          ),
          currentUserId: currentUserId,
          familyMembers: familyMembers,
        );

        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text:
              'Dạ! Em nhớ thói quen nhà mình thích uống "$savedPreference" rồi ạ. Em đã tạo ngay lời nhắc "$taskTitle" cho ${dadMember.name} vào lúc $targetTimeStr nhé! 🥛',
          timestamp: DateTime.now(),
          attachedReminder: created,
        );
      } else {
        // Lần đầu chưa biết -> Hỏi lại chi tiết và lưu trạng thái chờ
        _pendingClarifications[familyId] = PendingClarification(
          keyword: keyword,
          targetAssigneeId: dadMember.id,
          targetAssigneeName: dadMember.name,
          action: 'buy',
        );

        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: 'Dạ, mẹ muốn mua sữa gì ạ? (Vinamilk, TH True Milk, hay loại khác ạ?)',
          timestamp: DateTime.now(),
        );
      }
    }

    // 4. CASE 3: BÁO CÁO NHANH TIẾN ĐỘ GIA ĐÌNH HÔM NAY (REPORTING)
    // VD: "Tình hình ở nhà hôm nay sao rồi?", "Báo cáo hôm nay", "Tiến độ hôm nay"
    if (_isReportingIntent(lower)) {
      final allReminders = await repository.getReminders(familyId: familyId);
      final todayReminders = allReminders
          .where((r) => r.date == todayStr && !r.isDeleted)
          .toList();

      final total = todayReminders.length;
      final completed = todayReminders.where((r) => r.isCompleted).length;
      final overdue = todayReminders.where((r) => r.isOverdue).length;
      final pendingList = todayReminders
          .where((r) => r.isPending || r.isOpen)
          .toList();
      final pendingCount = pendingList.length;

      final percent = total > 0 ? ((completed / total) * 100).toInt() : 100;

      final buffer = StringBuffer();
      buffer.writeln('📊 BÁO CÁO TIẾN ĐỘ GIA ĐÌNH HÔM NAY ($todayStr):');
      buffer.writeln('• Tổng số công việc: $total việc');
      buffer.writeln('• Đã hoàn thành: $completed việc ($percent%)');
      buffer.writeln('• Đang chờ thực hiện: $pendingCount việc');
      if (overdue > 0) {
        buffer.writeln('• ⚠️ Có $overdue việc đã quá hạn cần hoàn tất gấp!');
      }

      if (pendingList.isNotEmpty) {
        buffer.writeln('\n📌 Danh sách công việc còn lại:');
        for (final r in pendingList.take(4)) {
          buffer.writeln(
              '  - ${r.title} (${r.isOpenTask ? "Việc chung" : r.assignedToName}) lúc ${r.time}');
        }
        if (pendingList.length > 4) {
          buffer.writeln('  ... và còn ${pendingList.length - 4} việc khác.');
        }
      } else {
        buffer.writeln('\n🎉 Xuất sắc! Tất cả công việc hôm nay đã được hoàn thành!');
      }

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: buffer.toString().trim(),
        timestamp: DateTime.now(),
      );
    }

    // 5. TRƯỜNG HỢP MẶC ĐỊNH / CHÀO HỎI / HƯỚNG DẪN
    return AiChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      isUser: false,
      text:
          'Xin chào $currentUserName! Em là Trợ lý AI Gia đình của bạn. Em có thể giúp bạn:\n\n'
          '• 🙋‍♂️ Giao việc chung cho các con (VD: "Hôm nay mẹ muốn làm việc nhà, có đứa nào phụ không?")\n'
          '• 🥛 Tự nhớ thói quen & tạo lời nhắc (VD: "Nhắc bố mua sữa")\n'
          '• 📊 Báo cáo tiến độ hôm nay (VD: "Tình hình ở nhà hôm nay sao rồi?")\n\n'
          'Bạn có thể gõ câu lệnh hoặc bấm vào các nút gợi ý nhanh bên dưới nhé! ❤️',
      timestamp: DateTime.now(),
    );
  }

  bool _isOpenTaskIntent(String text) {
    return text.contains('phụ không') ||
        text.contains('phụ mẹ') ||
        text.contains('phụ việc') ||
        text.contains('ai phụ') ||
        text.contains('cần người dọn') ||
        text.contains('tìm người phụ') ||
        text.contains('ai rảnh không') ||
        text.contains('làm việc nhà, có đứa nào');
  }

  bool _isMilkOrGroceryIntent(String text) {
    return text.contains('mua sữa') ||
        text.contains('nhắc mua sữa') ||
        text.contains('nhắc bố mua sữa') ||
        text.contains('giao mua sữa');
  }

  bool _isReportingIntent(String text) {
    return text.contains('tình hình') ||
        text.contains('báo cáo') ||
        text.contains('tiến độ') ||
        text.contains('sao rồi') ||
        text.contains('thế nào');
  }
}
