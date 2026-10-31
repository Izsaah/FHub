import 'dart:async';
import '../../Thinh/theme/app_language.dart';
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
  final List<ReminderModel> attachedReminders;
  final ReminderModel? suggestedReminder;
  final bool isSuggestionDismissed;
  final bool isSuggestionAccepted;

  const AiChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.attachedReminder,
    this.attachedReminders = const [],
    this.suggestedReminder,
    this.isSuggestionDismissed = false,
    this.isSuggestionAccepted = false,
  });

  List<ReminderModel> get allAttachedReminders {
    if (attachedReminders.isNotEmpty) return attachedReminders;
    if (attachedReminder != null) return [attachedReminder!];
    return const [];
  }

  AiChatMessage copyWith({
    String? id,
    bool? isUser,
    String? text,
    DateTime? timestamp,
    ReminderModel? attachedReminder,
    List<ReminderModel>? attachedReminders,
    ReminderModel? suggestedReminder,
    bool? isSuggestionDismissed,
    bool? isSuggestionAccepted,
  }) {
    return AiChatMessage(
      id: id ?? this.id,
      isUser: isUser ?? this.isUser,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      attachedReminder: attachedReminder ?? this.attachedReminder,
      attachedReminders: attachedReminders ?? this.attachedReminders,
      suggestedReminder: suggestedReminder ?? this.suggestedReminder,
      isSuggestionDismissed: isSuggestionDismissed ?? this.isSuggestionDismissed,
      isSuggestionAccepted: isSuggestionAccepted ?? this.isSuggestionAccepted,
    );
  }
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
/// - Xử lý NLU tiếng Việt & tiếng Anh tự nhiên, dễ tiếp cận cho mọi thành viên gia đình.
/// - Case 1: Giao việc mở cho các con (Open Task).
/// - Case 2: Cá nhân hóa & Nhớ thói quen (Personalization Memory - Vinamilk).
/// - Case 3: Báo cáo nhanh tiến độ công việc trong ngày.
/// - Case 4: Soạn & tạo cùng lúc 1 hoặc nhiều công việc tự nhiên (VD: "soạn các task dọn nhà, nấu cơm, rửa chén").
/// - Case 5: Hoàn thành hoặc xóa lời nhắc trực tiếp bằng giọng nói / tin nhắn.
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
    final targetDateStr = _formatDate(targetDt);
    final targetTimeStr = _formatTime(targetDt);
    final todayStr = _formatDate(effectiveNow);
    final salutation = _resolveSalutation(
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      familyMembers: familyMembers,
    );

    // 1. KIỂM TRA TRẠNG THÁI HỘI THOẠI ĐA LƯỢT (Case 2: Trả lời chi tiết thói quen)
    final pending = _pendingClarifications[familyId];
    if (pending != null) {
      if (lower == 'hủy' ||
          lower == 'thôi' ||
          lower == 'cancel' ||
          lower.contains('không mua') ||
          lower == 'bỏ qua') {
        _pendingClarifications.remove(familyId);
        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: AppLanguage.text(
            'Dạ, em đã hủy yêu cầu nhắc mua ${pending.keyword} rồi ạ! Gia đình mình cần em hỗ trợ việc gì khác cứ nói nhé! 😊',
            'Okay, I cancelled the request to buy ${pending.keyword}! Let me know if you need anything else! 😊',
          ),
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
      } else if (lower.contains('dutch lady') ||
          lower.contains('cô gái hà lan')) {
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
        attachedReminders: [created],
      );
    }

    // 2. CASE 1: GIAO VIỆC MỞ CHO CÁC CON (OPEN TASK)
    if (_isOpenTaskIntent(lower)) {
      String choreTitle = 'Phụ làm việc nhà';
      if (lower.contains('dọn nhà') || lower.contains('dọn dẹp')) {
        choreTitle = lower.contains('mẹ') ? 'Dọn dẹp nhà cửa phụ mẹ' : 'Dọn dẹp nhà cửa';
      } else if (lower.contains('nấu cơm') || lower.contains('nấu ăn')) {
        choreTitle = lower.contains('mẹ')
            ? 'Phụ mẹ nấu cơm chiều'
            : (lower.contains('bố') || lower.contains('ba')
                ? 'Phụ bố nấu cơm'
                : 'Nấu cơm chiều');
      } else if (lower.contains('rửa chén') ||
          lower.contains('rữa chén') ||
          lower.contains('rửa bát')) {
        choreTitle = lower.contains('mẹ') ? 'Rửa chén phụ mẹ' : 'Rửa chén bát';
      } else if (lower.contains('mẹ') || salutation == 'mẹ') {
        choreTitle = 'Phụ mẹ làm việc nhà';
      } else if (lower.contains('bố') || lower.contains('ba') || salutation == 'bố') {
        choreTitle = 'Phụ bố làm việc nhà';
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
            'Dạ $salutation! Em đã tạo một Công việc chung (Open Task) "$choreTitle" cho cả nhà rồi ạ. Các thành viên có thể bấm "Nhận việc ngay" trên thẻ dưới đây để xung phong làm nhé! 👨‍👩‍👧',
        timestamp: DateTime.now(),
        attachedReminder: created,
        attachedReminders: [created],
      );
    }

    // 3. CASE 2: CÁ NHÂN HÓA & NHỚ THÓI QUEN (PERSONALIZATION MEMORY)
    if (_isMilkOrGroceryIntent(lower)) {
      const keyword = 'sữa';
      final savedPreference = FamilyMemoryService.instance.getPreference(
        familyId: familyId,
        keyword: keyword,
      );

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
          attachedReminders: [created],
        );
      } else {
        _pendingClarifications[familyId] = PendingClarification(
          keyword: keyword,
          targetAssigneeId: dadMember.id,
          targetAssigneeName: dadMember.name,
          action: 'buy',
        );

        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text:
              'Dạ, $salutation muốn mua sữa gì ạ? (Vinamilk, TH True Milk, hay loại khác ạ?)',
          timestamp: DateTime.now(),
        );
      }
    }

    // 4. CASE 3: BÁO CÁO NHANH TIẾN ĐỘ GIA ĐÌNH HÔM NAY (REPORTING)
    if (_isReportingIntent(lower)) {
      final allReminders = await repository.getReminders(familyId: familyId);
      final todayReminders = allReminders
          .where((r) => r.date == todayStr && !r.isDeleted)
          .toList();

      final total = todayReminders.length;
      final completed = todayReminders.where((r) => r.isCompleted).length;
      final overdue = todayReminders.where((r) => r.isOverdue).length;
      final pendingList =
          todayReminders.where((r) => r.isPending || r.isOpen).toList();
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
        for (final r in pendingList.take(5)) {
          buffer.writeln(
              '  - ${r.title} (${r.isOpenTask ? "Việc chung" : r.assignedToName}) lúc ${r.time}');
        }
        if (pendingList.length > 5) {
          buffer.writeln('  ... và còn ${pendingList.length - 5} việc khác.');
        }
      } else {
        buffer.writeln(
            '\n🎉 Xuất sắc! Tất cả công việc hôm nay đã được hoàn thành!');
      }

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: buffer.toString().trim(),
        timestamp: DateTime.now(),
      );
    }

    // 5. CASE 4: XÓA HOẶC HOÀN THÀNH CÔNG VIỆC BẰNG LỆNH CHAT / GIỌNG NÓI
    if (_isDeleteTaskIntent(lower)) {
      final targetTitle = _extractTargetTaskTitleForAction(query);
      final allReminders = await repository.getReminders(familyId: familyId);
      final activeReminders =
          allReminders.where((r) => !r.isDeleted).toList();
      final matched = activeReminders.where((r) {
        final t = r.title.toLowerCase();
        return targetTitle.isNotEmpty &&
            (t.contains(targetTitle) || targetTitle.contains(t));
      }).toList();

      if (matched.isNotEmpty) {
        final toDelete = matched.first;
        try {
          await repository.deleteReminder(
            reminderId: toDelete.id,
            currentUserId: currentUserId,
            familyMembers: familyMembers,
          );
          return AiChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            text: AppLanguage.text(
              '🗑️ Dạ em đã xóa lời nhắc "${toDelete.title}" khỏi danh sách công việc rồi ạ!',
              '🗑️ I have deleted the reminder "${toDelete.title}" from your task list!',
            ),
            timestamp: DateTime.now(),
          );
        } catch (e) {
          return AiChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            text: AppLanguage.text(
              'Dạ không thể xóa công việc "${toDelete.title}": $e',
              'Could not delete task "${toDelete.title}": $e',
            ),
            timestamp: DateTime.now(),
          );
        }
      }
    }

    if (_isCompleteTaskIntent(lower)) {
      final targetTitle = _extractTargetTaskTitleForAction(query);
      final allReminders = await repository.getReminders(familyId: familyId);
      final pendingReminders = allReminders
          .where((r) => !r.isDeleted && !r.isCompleted)
          .toList();
      final matched = pendingReminders.where((r) {
        final t = r.title.toLowerCase();
        return targetTitle.isNotEmpty &&
            (t.contains(targetTitle) || targetTitle.contains(t));
      }).toList();

      if (matched.isNotEmpty) {
        final toComplete = matched.first;
        try {
          if (toComplete.isOpenTask) {
            await repository.claimOpenTask(
              reminderId: toComplete.id,
              currentUserId: currentUserId,
              currentUserName: currentUserName,
            );
          }
          await repository.completeReminder(
            reminderId: toComplete.id,
            currentUserId: currentUserId,
          );
          return AiChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            text: AppLanguage.text(
              '✅ Tuyệt vời! Em đã đánh dấu hoàn thành công việc "${toComplete.title}" giúp bạn rồi nhé!',
              '✅ Awesome! I have marked "${toComplete.title}" as completed for you!',
            ),
            timestamp: DateTime.now(),
          );
        } catch (_) {}
      }
    }

    // 6. CASE 5: SOẠN & TẠO 1 HOẶC NHIỀU CÔNG VIỆC TỰ NHIÊN
    // VD: "soạn các task dọn nhà, nấu cơm, rữa chén", "nhắc lau nhà lúc 18:00", "tạo việc đi chợ, nấu ăn"
    final parsedTasks = _tryExtractTaskTitles(query, lower);
    if (parsedTasks.isNotEmpty) {
      final assignee = _resolveAssignee(
        lower: lower,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
        familyMembers: familyMembers,
      );
      final isOpen = assignee.id == 'OPEN';
      final customDate = _extractCustomDate(lower, effectiveNow);
      final customTime = _extractCustomTime(lower);

      final List<ReminderModel> createdList = [];
      for (int i = 0; i < parsedTasks.length; i++) {
        final title = parsedTasks[i];
        // Nếu người dùng không chỉ định giờ cụ thể, giãn cách mỗi việc 30 phút bắt đầu từ +1 giờ
        final taskDt = effectiveNow.add(Duration(minutes: 60 + (i * 30)));
        final timeStr = customTime ?? _formatTime(taskDt);
        final dateStr = customDate ?? _formatDate(taskDt);

        final created = await repository.createReminder(
          reminder: ReminderModel(
            id: 'rem_${DateTime.now().millisecondsSinceEpoch}_$i',
            familyId: familyId,
            creatorId: currentUserId,
            creatorName: currentUserName,
            assignedTo: assignee.id,
            assignedToName: assignee.name,
            title: title,
            date: dateStr,
            time: timeStr,
            status: isOpen ? ReminderStatus.open : ReminderStatus.pending,
            createdAt: DateTime.now(),
          ),
          currentUserId: currentUserId,
          familyMembers: familyMembers,
        );
        createdList.add(created);
      }

      if (createdList.length == 1) {
        final single = createdList.first;
        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: AppLanguage.text(
            'Dạ xong ngay ạ! Em đã tạo lời nhắc "${single.title}" cho ${single.assignedToName} vào lúc ${single.time} ngày ${single.date} rồi nhé! ✅',
            'Done! I have created the reminder "${single.title}" for ${single.assignedToName} at ${single.time} on ${single.date}! ✅',
          ),
          timestamp: DateTime.now(),
          attachedReminder: single,
          attachedReminders: createdList,
        );
      } else {
        final buffer = StringBuffer();
        buffer.writeln(
          AppLanguage.text(
            'Dạ em đã soạn và tạo xong ${createdList.length} công việc cho ${assignee.name} rồi ạ! ✅\n',
            'I have created ${createdList.length} tasks for ${assignee.name}! ✅\n',
          ),
        );
        for (int i = 0; i < createdList.length; i++) {
          final item = createdList[i];
          buffer.writeln('${i + 1}. 📌 ${item.title} (${item.time} • ${item.date})');
        }
        buffer.write(
          AppLanguage.text(
            '\nBạn có thể chạm vào từng thẻ công việc bên dưới để xem chi tiết hoặc chỉnh sửa nhé!',
            '\nYou can tap any task card below to view details or edit it!',
          ),
        );

        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: buffer.toString().trim(),
          timestamp: DateTime.now(),
          attachedReminder: createdList.first,
          attachedReminders: createdList,
        );
      }
    }

    // 7. CASE 6: GỢI Ý KẾ HOẠCH NẤU ĂN / VIỆC NHÀ TỰ NHIÊN (SUGGESTION SCANNING)
    final detectedDish = _detectDishOrActivity(lower);
    if (detectedDish != null && _isPlanOrCookingIntent(lower, detectedDish)) {
      final dishCapitalized = _capitalizeFirst(detectedDish);
      final isRecipe = lower.contains('cách nấu') ||
          lower.contains('thế nào') ||
          lower.contains('như thế nào') ||
          lower.contains('công thức') ||
          lower.contains('hướng dẫn');

      if (isRecipe) {
        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: AppLanguage.text(
            '🍲 Bí quyết nấu món $dishCapitalized thơm ngon:\n'
            '• Ướp gia vị (hành, tỏi băm, nước mắm, tiêu) khoảng 15-20 phút cho thấm sâu.\n'
            '• Đun nhỏ lửa liu riu để nguyên liệu chín mềm, nước sốt sánh mịn đậm đà vị nhà làm!\n\n'
            'Em có gợi ý tạo lời nhắc "Mua nguyên liệu nấu $dishCapitalized" bên dưới, $salutation có muốn tạo cho gia đình không ạ?',
            '🍲 Tips for making $dishCapitalized:\n'
            '• Marinate with spices for 15-20 minutes.\n'
            '• Simmer on low heat until tender and flavorful!\n\n'
            'I suggested a reminder "Buy ingredients for $dishCapitalized" below, would you like to create it?',
          ),
          timestamp: DateTime.now(),
          suggestedReminder: ReminderModel(
            id: 'sug_${DateTime.now().millisecondsSinceEpoch}',
            familyId: familyId,
            creatorId: currentUserId,
            creatorName: currentUserName,
            assignedTo: 'OPEN',
            assignedToName: 'Cả nhà (Việc chung)',
            title: 'Mua nguyên liệu nấu $dishCapitalized',
            date: targetDateStr,
            time: targetTimeStr,
            status: ReminderStatus.open,
            createdAt: DateTime.now(),
            voiceNoteDescription: 'Chuẩn bị gia vị và nguyên liệu tươi ngon nấu $dishCapitalized theo kế hoạch của $currentUserName.',
          ),
        );
      } else {
        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: AppLanguage.text(
            'Món $dishCapitalized ăn cùng cơm nóng trong bữa cơm gia đình thì ngon và ấm cúng lắm ạ! 🍲 Em thấy $salutation đang có kế hoạch làm món này, $salutation có muốn em tạo lời nhắc "Mua nguyên liệu nấu $dishCapitalized" để cả nhà cùng phụ chuẩn bị không ạ?',
            'Cooking $dishCapitalized for family meal sounds delicious! 🍲 I see you are planning to make this, would you like me to create a reminder "Buy ingredients for $dishCapitalized" for the family?',
          ),
          timestamp: DateTime.now(),
          suggestedReminder: ReminderModel(
            id: 'sug_${DateTime.now().millisecondsSinceEpoch}',
            familyId: familyId,
            creatorId: currentUserId,
            creatorName: currentUserName,
            assignedTo: 'OPEN',
            assignedToName: 'Cả nhà (Việc chung)',
            title: 'Mua nguyên liệu nấu $dishCapitalized',
            date: targetDateStr,
            time: targetTimeStr,
            status: ReminderStatus.open,
            createdAt: DateTime.now(),
            voiceNoteDescription: 'Chuẩn bị nguyên liệu tươi ngon cho món $dishCapitalized theo kế hoạch của $currentUserName.',
          ),
        );
      }
    }

    // 8. CASE 7: HỘI THOẠI TỰ NHIÊN, CHÀO HỎI & ĐỘNG VIÊN
    if (lower.contains('chào') ||
        lower.contains('hello') ||
        lower.contains('hi ai') ||
        lower == 'hi' ||
        lower == 'hey') {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ em chào $salutation! Chúc $salutation và gia đình một ngày thật vui vẻ và bình an. Em có thể hỗ trợ $salutation việc gì hôm nay ạ? ❤️',
          'Hello $salutation! Wishing you and your family a wonderful day. How can I assist you today? ❤️',
        ),
        timestamp: DateTime.now(),
      );
    }

    if (lower.contains('mệt') || lower.contains('đuối') || lower.contains('căng thẳng')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ thương $salutation quá! Cả ngày bận rộn lo toan rồi, $salutation nhớ nghỉ ngơi, uống ly nước ấm nhé. Việc nhà cứ để em lên lịch nhắc các thành viên cùng chia sẻ gánh vác nhé! 🌿',
          'Take a rest $salutation! You worked hard today. Stay hydrated and rest; I can help schedule chores for everyone to share! 🌿',
        ),
        timestamp: DateTime.now(),
      );
    }

    if (lower.contains('cảm ơn') ||
        lower.contains('thank') ||
        lower.contains('tuyệt vời') ||
        lower.contains('hay quá') ||
        lower == 'ok' ||
        lower == 'oke') {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ không có gì đâu ạ! ❤️ Giúp gia đình mình sắp xếp việc nhà gọn gàng là niềm vui của em. Khi nào cần tạo việc hay kiểm tra tiến độ, $salutation cứ gọi hoặc nhắn em nhé!',
          'You are very welcome! ❤️ Helping your family stay organized is my pleasure. Just speak or type whenever you need me!',
        ),
        timestamp: DateTime.now(),
      );
    }

    return AiChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      isUser: false,
      text: AppLanguage.text(
        'Dạ em đã nhận được lời nhắn của $salutation rồi ạ! $salutation có thể giao việc, chia sẻ dự định nấu ăn (VD: "Tối nay nấu thịt kho"), hoặc hỏi thăm tiến độ gia đình bất cứ lúc nào nhé. Em luôn sẵn sàng hỗ trợ! 😊',
        'I received your message $salutation! You can assign tasks, share cooking plans (e.g. "Cooking dinner tonight"), or check progress anytime. I am always here to assist! 😊',
      ),
      timestamp: DateTime.now(),
    );
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _resolveSalutation({
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMember> familyMembers,
  }) {
    final member = familyMembers.where((m) => m.id == currentUserId).firstOrNull;
    final nameLower = currentUserName.toLowerCase();
    if (nameLower.contains('mẹ') || nameLower.contains('má') || nameLower.contains('mom')) {
      return 'mẹ';
    }
    if (nameLower.contains('bố') || nameLower.contains('ba') || nameLower.contains('cha') || nameLower.contains('dad')) {
      return 'bố';
    }
    if (member != null && member.isParent) {
      return currentUserName;
    }
    return currentUserName;
  }

  String? _detectDishOrActivity(String lower) {
    const dishes = [
      'thịt kho tàu',
      'thịt kho tiêu',
      'thịt kho',
      'sườn xào chua ngọt',
      'sườn xào',
      'canh chua cá lóc',
      'canh chua',
      'cá kho tộ',
      'cá kho',
      'lẩu hải sản',
      'lẩu thái',
      'lẩu gà',
      'lẩu',
      'bò kho',
      'bánh xèo',
      'bún bò huế',
      'bún bò',
      'gà rán',
      'chả giò',
      'nem rán',
      'thịt luộc',
      'trứng chiên',
      'canh rau',
      'canh bí',
      'rau xào',
      'mì ý',
      'pizza',
      'bbq',
    ];

    for (final dish in dishes) {
      if (lower.contains(dish)) {
        return dish;
      }
    }
    return null;
  }

  bool _isPlanOrCookingIntent(String lower, String dish) {
    const planKeywords = [
      'nấu',
      'làm',
      'ăn',
      'kho',
      'chiên',
      'xào',
      'luộc',
      'nướng',
      'tối nay',
      'trưa nay',
      'chiều nay',
      'ngày mai',
      'sẽ',
      'có lẽ',
      'định',
      'chắc',
      'chuẩn bị',
      'kế hoạch',
      'hôm nay',
      'cách',
      'công thức',
      'hướng dẫn',
      'thế nào',
    ];
    return planKeywords.any((k) => lower.contains(k));
  }

  bool _isOpenTaskIntent(String text) {
    return text.contains('phụ không') ||
        text.contains('phụ việc') ||
        text.contains('ai phụ') ||
        text.contains('ai muốn phụ') ||
        text.contains('ai giúp') ||
        text.contains('ai rảnh') ||
        text.contains('cần người dọn') ||
        text.contains('tìm người phụ') ||
        text.contains('làm việc nhà, có đứa nào') ||
        (text.contains('phụ') && (text.contains('nấu') || text.contains('dọn') || text.contains('rửa')));
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
        text.contains('hôm nay có việc gì') ||
        text.contains('việc gì chưa làm') ||
        text.contains('danh sách công việc') ||
        text.contains('danh sách việc') ||
        text.contains('tổng kết') ||
        text.contains('việc nhà thế nào') ||
        text.contains('ở nhà thế nào') ||
        text.contains('công việc thế nào') ||
        (text.contains('thế nào') &&
            (text.contains('nhà') ||
                text.contains('việc') ||
                text.contains('hôm nay')));
  }

  bool _isDeleteTaskIntent(String text) {
    return text.startsWith('xóa task') ||
        text.startsWith('xóa việc') ||
        text.startsWith('xóa lời nhắc') ||
        text.startsWith('hủy việc') ||
        text.startsWith('hủy lời nhắc') ||
        text.startsWith('delete task') ||
        text.startsWith('remove task');
  }

  bool _isCompleteTaskIntent(String text) {
    return text.startsWith('hoàn thành') ||
        text.startsWith('xong việc') ||
        text.startsWith('đã làm xong') ||
        text.startsWith('complete task') ||
        text.startsWith('finish task');
  }

  String _extractTargetTaskTitleForAction(String raw) {
    var cleaned = raw.trim();
    final prefixes = [
      RegExp(
        r'^(xóa\s+task|xóa\s+việc|xóa\s+lời\s+nhắc|hủy\s+việc|hủy\s+lời\s+nhắc|hoàn\s+thành\s+việc|hoàn\s+thành\s+task|hoàn\s+thành|xong\s+việc|đã\s+làm\s+xong|delete\s+task|remove\s+task|complete\s+task|finish\s+task)\s*:?\s*',
        caseSensitive: false,
      ),
    ];
    for (final p in prefixes) {
      cleaned = cleaned.replaceFirst(p, '');
    }
    return cleaned.replaceAll(RegExp(r'["\x27]'), '').trim().toLowerCase();
  }

  /// Trích xuất danh sách tên công việc từ câu lệnh tự nhiên của người dùng
  List<String> _tryExtractTaskTitles(String rawQuery, String lower) {
    // Kiểm tra xem câu có chứa ý định tạo việc hoặc chứa tên các việc nhà phổ biến không
    final hasTaskKeyword = RegExp(
      r'(soạn|tạo|thêm|nhắc|giao|lên\s+lịch|đặt\s+lịch|task|tasks|công\s+việc|lời\s+nhắc|việc\s+cần\s+làm|remind|create|add|todo)',
      caseSensitive: false,
    ).hasMatch(lower);

    final hasCommonChore = RegExp(
      r'(dọn\s+nhà|dọn\s+dẹp|dọn\s+phòng|lau\s+nhà|quét\s+nhà|nấu\s+cơm|nấu\s+ăn|rửa\s+chén|rữa\s+chén|rửa\s+bát|rữa\s+bát|giặt\s+đồ|giặt\s+quần\s+áo|phơi\s+đồ|gấp\s+quần\s+áo|đổ\s+rác|tưới\s+cây|đi\s+chợ|đi\s+siêu\s+thị|mua\s+đồ|học\s+bài|uống\s+thuốc|tập\s+thể\s+dục|đón\s+con|cho\s+cá\s+ăn|cho\s+chó\s+ăn|cho\s+mèo\s+ăn|cọ\s+toilet|lau\s+bàn|lau\s+bếp)',
      caseSensitive: false,
    ).hasMatch(lower);

    if (!hasTaskKeyword && !hasCommonChore) {
      return const [];
    }

    var working = rawQuery.trim();

    // 1. Loại bỏ phần thời gian ở cuối hoặc giữa câu (VD: "lúc 18:00", "vào 7h sáng", "hôm nay", "ngày mai")
    working = working.replaceAll(
      RegExp(
        r'\s+(vào\s+lúc|vào|lúc|at)\s+\d{1,2}(:\d{2}|h\d{0,2}|\s*giờ(\s*\d{1,2}\s*phút)?)(\s*(sáng|trưa|chiều|tối|am|pm))?',
        caseSensitive: false,
      ),
      '',
    );
    working = working.replaceAll(
      RegExp(
        r'\s+(hôm\s+nay|ngày\s+mai|tối\s+nay|chiều\s+nay|sáng\s+nay|trưa\s+nay|today|tomorrow)\s*$',
        caseSensitive: false,
      ),
      '',
    );

    // 2. Loại bỏ tiền tố câu lệnh (VD: "soạn các task", "tạo lời nhắc", "nhắc tôi", "giao việc", v.v.)
    final prefixRegex = RegExp(
      r'^(em\s+ơi\s*,?\s*|ai\s+ơi\s*,?\s*|bạn\s+ơi\s*,?\s*)?'
      r'(hãy\s+|giúp\s+tôi\s+|giúp\s+mình\s+|giúp\s+em\s+|vui\s+lòng\s+)?'
      r'(soạn|tạo|thêm|lên\s+lịch|đặt\s+lịch|nhắc\s+nhở|nhắc|giao|create|add|remind(\s+me)?(\s+to)?)\s*'
      r'(giúp\s+tôi\s+|giúp\s+mình\s+|cho\s+tôi\s+|cho\s+mình\s+|tôi\s+|mình\s+|em\s+|bố\s+|mẹ\s+|ba\s+|má\s+|con\s+)?'
      r'(các\s+|những\s+|một\s+số\s+|mấy\s+|1\s+|một\s+)?'
      r'(task|tasks|công\s+việc|lời\s+nhắc|việc\s+nhà|việc)?\s*'
      r'(như\s+sau|sau\s+đây|là|gồm)?\s*:?\s*',
      caseSensitive: false,
    );
    working = working.replaceFirst(prefixRegex, '').trim();

    // Loại bỏ hậu tố lịch sự cuối câu (VD: "nhé", "nha", "ạ", "giúp mình")
    working = working.replaceAll(
      RegExp(
        r'\s+(nhé|nha|nhá|ạ|giúp\s+tôi|giúp\s+mình|giúp\s+em|cho\s+tôi|cho\s+mình|cho\s+cả\s+nhà)[.!?]*$',
        caseSensitive: false,
      ),
      '',
    );

    if (working.isEmpty) return const [];

    // 3. Tách danh sách công việc theo dấu phẩy (,), chấm phẩy (;), xuống dòng, hoặc từ nối " và " / " and "
    final rawParts = working
        .split(RegExp(r'\s*(?:,|;|\n|\s+và\s+|\s+với\s+|\s+and\s+)\s*', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final List<String> cleanedTasks = [];
    for (var part in rawParts) {
      // Bỏ từ "task ", "việc " nếu lặp lại ở từng vế
      part = part
          .replaceFirst(
            RegExp(r'^(các\s+)?(task|tasks|công\s+việc|việc|lời\s+nhắc)\s*:?\s*',
                caseSensitive: false),
            '',
          )
          .trim();

      // Chuẩn hóa lỗi chính tả tiếng Việt phổ biến
      part = _normalizeVietnameseTypos(part);

      if (part.isNotEmpty && part.length >= 2) {
        cleanedTasks.add(_capitalizeFirst(part));
      }
    }

    return cleanedTasks;
  }

  String _normalizeVietnameseTypos(String input) {
    var out = input;
    final replacements = <RegExp, String>{
      RegExp(r'rữa\s+chén', caseSensitive: false): 'rửa chén',
      RegExp(r'rữa\s+bát', caseSensitive: false): 'rửa bát',
      RegExp(r'nấu\s+com', caseSensitive: false): 'nấu cơm',
      RegExp(r'dọn\s+nha\b', caseSensitive: false): 'dọn nhà',
      RegExp(r'lau\s+nha\b', caseSensitive: false): 'lau nhà',
      RegExp(r'quét\s+nha\b', caseSensitive: false): 'quét nhà',
      RegExp(r'giặt\s+đô\b', caseSensitive: false): 'giặt đồ',
      RegExp(r'đổ\s+rac\b', caseSensitive: false): 'đổ rác',
    };
    replacements.forEach((regex, replacement) {
      out = out.replaceAll(regex, replacement);
    });
    return out;
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  String? _extractCustomTime(String lower) {
    // Khớp định dạng HH:mm hoặc HHh(mm) (VD: 18:00, 18h30, 7h sáng, 8h tối)
    final match = RegExp(
      r'(\d{1,2})(?::(\d{2})|h(\d{0,2})|\s*giờ(?:\s*(\d{1,2}))?)(?:\s*(sáng|trưa|chiều|tối|am|pm))?',
      caseSensitive: false,
    ).firstMatch(lower);

    if (match != null) {
      int hour = int.tryParse(match.group(1) ?? '') ?? 9;
      final minStr = match.group(2) ?? match.group(3) ?? match.group(4) ?? '00';
      final minute = (int.tryParse(minStr.isEmpty ? '0' : minStr) ?? 0).clamp(0, 59);
      final period = (match.group(5) ?? '').toLowerCase();

      if ((period == 'chiều' || period == 'tối' || period == 'pm') && hour < 12) {
        hour += 12;
      } else if ((period == 'sáng' || period == 'am') && hour == 12) {
        hour = 0;
      }
      hour = hour.clamp(0, 23);
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    if (lower.contains('sáng mai') || lower.contains('buổi sáng')) return '08:00';
    if (lower.contains('buổi trưa') || lower.contains('trưa nay')) return '12:00';
    if (lower.contains('buổi chiều') || lower.contains('chiều nay')) return '17:00';
    if (lower.contains('buổi tối') || lower.contains('tối nay')) return '19:30';
    return null;
  }

  String? _extractCustomDate(String lower, DateTime now) {
    if (lower.contains('ngày mai') ||
        lower.contains('sáng mai') ||
        lower.contains('chiều mai') ||
        lower.contains('tối mai') ||
        lower.contains('tomorrow')) {
      return _formatDate(now.add(const Duration(days: 1)));
    }
    return null;
  }

  FamilyMember _resolveAssignee({
    required String lower,
    required String currentUserId,
    required String currentUserName,
    required List<FamilyMember> familyMembers,
  }) {
    if (lower.contains('việc chung') ||
        lower.contains('cả nhà') ||
        lower.contains('ai làm cũng được')) {
      return const FamilyMember(
        id: 'OPEN',
        name: 'Cả nhà (Việc chung)',
        role: FamilyMember.roleChild,
        familyId: '',
      );
    }

    // Kiểm tra xem có nhắc tên thành viên nào trong gia đình không
    for (final member in familyMembers) {
      final mName = member.name.toLowerCase();
      if (mName.isNotEmpty && lower.contains(mName)) {
        return member;
      }
    }

    if (lower.contains('cho bố') ||
        lower.contains('nhắc bố') ||
        lower.contains('nhắc ba')) {
      final dad = familyMembers.where((m) {
        final n = m.name.toLowerCase();
        return n.contains('bố') || n.contains('ba') || n.contains('dad');
      }).firstOrNull;
      if (dad != null) return dad;
    }

    if (lower.contains('cho mẹ') ||
        lower.contains('nhắc mẹ') ||
        lower.contains('nhắc má')) {
      final mom = familyMembers.where((m) {
        final n = m.name.toLowerCase();
        return n.contains('mẹ') || n.contains('má') || n.contains('mom');
      }).firstOrNull;
      if (mom != null) return mom;
    }

    return FamilyMember(
      id: currentUserId,
      name: currentUserName,
      role: FamilyMember.roleParent,
      familyId: '',
    );
  }
}
