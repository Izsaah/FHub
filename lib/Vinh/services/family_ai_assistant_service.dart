import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../Ai/services/gemini_chat_service.dart';
import '../../Long/services/family_state_manager.dart';
import '../../Thinh/theme/app_language.dart';
import '../models/family_member.dart';
import '../models/reminder_model.dart';
import '../../Ai/services/family_memory_service.dart';
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'isUser': isUser,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'attachedReminder': attachedReminder?.toMap(),
      'attachedReminders': attachedReminders.map((r) => r.toMap()).toList(),
      'suggestedReminder': suggestedReminder?.toMap(),
      'isSuggestionDismissed': isSuggestionDismissed,
      'isSuggestionAccepted': isSuggestionAccepted,
    };
  }

  factory AiChatMessage.fromMap(String docId, Map<String, dynamic> map) {
    DateTime ts;
    final rawTs = map['timestamp'];
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    ReminderModel? attRem;
    if (map['attachedReminder'] is Map) {
      final remData = Map<String, dynamic>.from(map['attachedReminder'] as Map);
      attRem = ReminderModel.fromMap(remData['id']?.toString() ?? '', remData);
    }

    final List<ReminderModel> attList = [];
    if (map['attachedReminders'] is List) {
      for (final item in (map['attachedReminders'] as List)) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          attList.add(ReminderModel.fromMap(m['id']?.toString() ?? '', m));
        }
      }
    }

    ReminderModel? sugRem;
    if (map['suggestedReminder'] is Map) {
      final remData = Map<String, dynamic>.from(map['suggestedReminder'] as Map);
      sugRem = ReminderModel.fromMap(remData['id']?.toString() ?? '', remData);
    }

    return AiChatMessage(
      id: docId,
      isUser: map['isUser'] == true,
      text: map['text']?.toString() ?? '',
      timestamp: ts,
      attachedReminder: attRem,
      attachedReminders: attList,
      suggestedReminder: sugRem,
      isSuggestionDismissed: map['isSuggestionDismissed'] == true,
      isSuggestionAccepted: map['isSuggestionAccepted'] == true,
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

  /// Xóa phiên trò chuyện của gia đình hiện tại
  void reset(String familyId) {
    _pendingClarifications.remove(familyId);
    GeminiChatService.instance.resetChatSession();
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
    bool checkThrottle = false,
  }) async {
    final query = userMessage.trim();
    if (query.isEmpty) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: 'Vui lòng nhập nội dung tin nhắn.',
        timestamp: DateTime.now(),
      );
    }

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

    // ƯU TIÊN SỐ 1 TUYỆT ĐỐI: GỌI GEMINI LLM THẾ HỆ MỚI
    // Tự do 100%, không bị gò bó bởi regex hay mẫu câu đóng khung
    if (GeminiChatService.instance.isConfigured) {
      try {
        final myMember = familyMembers.where((m) => m.id == currentUserId).firstOrNull;
        final myRole = myMember?.roleDisplayName ?? (myMember?.isParent == true ? 'Phụ huynh' : 'Thành viên');

        final geminiRes = await GeminiChatService.instance.sendMessage(
          query,
          familyId: familyId,
          userId: currentUserId,
          userName: currentUserName,
          userRole: myRole,
          familyMembers: familyMembers,
          fallbackToLocal: false,
          checkThrottle: checkThrottle,
        );

        if (!geminiRes.isError && geminiRes.text.trim().isNotEmpty) {
          if (geminiRes.createdTask != null) {
            try {
              await repository.createReminder(
                reminder: geminiRes.createdTask!,
                currentUserId: currentUserId,
                familyMembers: familyMembers,
              );
            } catch (_) {}
            return AiChatMessage(
              id: geminiRes.id,
              isUser: false,
              text: geminiRes.text.trim(),
              timestamp: geminiRes.timestamp,
              attachedReminder: geminiRes.createdTask,
              attachedReminders: [geminiRes.createdTask!],
            );
          }

          return AiChatMessage(
            id: geminiRes.id,
            isUser: false,
            text: geminiRes.text.trim(),
            timestamp: geminiRes.timestamp,
          );
        }
      } catch (e) {
        debugPrint('Gemini Chat online call failed, switching to local assistant: $e');
      }
    }

    // 1. KIỂM TRA TRẠNG THÁI HỘI THOẠI ĐA LƯỢT (Case 2: Trả lời chi tiết thói quen khi Offline)
    final pending = _pendingClarifications[familyId];
    if (pending != null) {
      final isCancel = lower == 'hủy' ||
          lower == 'thôi' ||
          lower == 'cancel' ||
          lower.contains('không mua') ||
          lower == 'bỏ qua' ||
          lower.startsWith('thôi không');

      final isTopicChange = lower.startsWith('à không') ||
          lower.contains('bữa tiệc') ||
          lower.contains('nấu ăn') ||
          lower.contains('dọn nhà') ||
          lower.contains('quét nhà') ||
          query.length > 35;

      if (isCancel || isTopicChange) {
        _pendingClarifications.remove(familyId);
        if (!isTopicChange) {
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
        // Nếu là chuyển chủ đề (VD: đổi sang muốn nấu tiệc), tiếp tục xử lý intent bên dưới, không gán vào sữa!
      } else {
        _pendingClarifications.remove(familyId);

        String preference = query
            .replaceAll(RegExp(r'^(của|hiệu|tiệm|quán|ở|mua\s+ở)\s+', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*,\s*(tạo\s+lịch|tạo\s+việc|lên\s+lịch|giao\s+việc|thành\s+viên).*$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*(nha|nhé|nhá|ạ|đi|giúp\s+mình|giúp\s+tôi)[\s.!]*$', caseSensitive: false), '')
            .trim();
        if (preference.isEmpty) {
          preference = query.trim();
        }

        await FamilyMemoryService.instance.savePreference(
          familyId: familyId,
          keyword: pending.keyword,
          preference: preference,
        );

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
    }

    // 1.4. CASE: YÊU CẦU ĐIỂM DANH / TÍCH "I'M OK" (THAO TÁC THỰC THI TRỰC TIẾP)
    if (_isPerformCheckInIntent(lower)) {
      final myMember = familyMembers.where((m) => m.id == currentUserId).firstOrNull;
      final isChild = myMember?.isChild == true || myMember?.canAssignChores == false;
      if (isChild) {
        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: AppLanguage.text(
            'Dạ $salutation ơi! Để Bố Mẹ thực sự yên tâm khi thấy $salutation an toàn hôm nay, $salutation hãy bấm nút "✓ I\'M OK" trên màn hình chính và chụp một tấm ảnh gửi về gia đình nhé! 📸💚',
            'Hello $salutation! To give your parents peace of mind that you are truly safe today, please tap the "✓ I\'M OK" button on the home screen and take a photo to check in! 📸💚',
          ),
          timestamp: DateTime.now(),
        );
      }

      await _executeCheckInAction(
        familyId: familyId,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      );

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ em đã tích "I\'m OK" và hoàn tất điểm danh hôm nay cho $salutation rồi nhé! 💚✨\n'
          'Trạng thái an tâm của $salutation đã được cập nhật đồng loạt cho cả gia đình cùng thấy. Chúc $salutation một ngày thật vui vẻ và tràn đầy năng lượng! 🌟',
          'I have checked in "I\'m OK" for you today, $salutation! 💚✨\nYour safe status has been updated across the family. Wishing you a wonderful and energetic day! 🌟',
        ),
        timestamp: DateTime.now(),
      );
    }

    // 1.5. CASE: HỎI VỀ ĐIỂM DANH / CHECK-IN HÔM NAY
    if (_isCheckInIntent(lower)) {
      final buffer = StringBuffer();
      buffer.writeln('📋 TÌNH HÌNH ĐIỂM DANH GIA ĐÌNH HÔM NAY ($todayStr):');
      buffer.writeln('• Chưa có thành viên nào ghi nhận điểm danh hôm nay.');
      if (familyMembers.isNotEmpty) {
        buffer.writeln('\n⏳ Danh sách thành viên gia đình:');
        for (final m in familyMembers) {
          buffer.writeln('  • ${m.name} (${m.roleDisplayName})');
        }
      }
      buffer.write('\nDạ $salutation, cả nhà nhớ mở app bấm Điểm danh hôm nay để nhận sao thưởng nhé! ❤️');

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: buffer.toString().trim(),
        timestamp: DateTime.now(),
      );
    }

    // 1.8. CASE: HỎI VỀ VAI TRÒ & QUYỀN HẠN CỦA BẢN THÂN TRONG GIA ĐÌNH
    // Phải xử lý trước khi tạo việc để các câu hỏi "tôi đóng vai trò gì, có thể giao việc cho ai không" không bị parse thành task!
    if (_isRoleOrIdentityIntent(lower)) {
      final myMember = familyMembers.where((m) => m.id == currentUserId).firstOrNull;
      String roleDisplay;
      if (myMember?.isParent == true) {
        final nameLower = currentUserName.toLowerCase();
        if (nameLower.contains('mẹ') || nameLower.contains('má') || nameLower.contains('mom')) {
          roleDisplay = 'Mẹ (Phụ huynh)';
        } else if (nameLower.contains('bố') || nameLower.contains('ba') || nameLower.contains('cha') || nameLower.contains('dad')) {
          roleDisplay = 'Bố (Phụ huynh)';
        } else {
          roleDisplay = 'Phụ huynh (Quản trị gia đình)';
        }
      } else if (myMember?.isChild == true) {
        roleDisplay = 'Con cái (Thành viên tích cực)';
      } else if (myMember?.isGrandparent == true) {
        roleDisplay = 'Ông Bà (Trưởng bối)';
      } else {
        roleDisplay = 'Thành viên gia đình';
      }
      final desc = myMember?.isParent == true
          ? 'Bạn giữ quyền **Phụ huynh (Bố Mẹ - Quản trị gia đình)**: Có toàn quyền giao việc cho con cái, tạo việc chung, duyệt quà đổi sao và mở Heo Đất / Nổ Hũ khen thưởng cho cả nhà nhé! 👑'
          : (myMember?.isGrandparent == true
              ? 'Bạn là **Ông Bà (Trưởng bối)**: Có quyền giao việc, gắn kết các thế hệ và cùng theo dõi tiến độ gia đình ấm cúng! 🏡'
              : 'Bạn là **Con cái (Thành viên tích cực)**: Có thể xung phong nhận các công việc chung trên bảng việc, hoàn thành nhiệm vụ để tích lũy sao thưởng nuôi Heo Đất và đổi những món quà mơ ước trong Cửa hàng phúc lợi nhé! 🌟');

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ $salutation! Trong gia đình mình, vai trò của bạn là **$roleDisplay**.\n\n$desc',
          'Hello $salutation! In your family, your role is **$roleDisplay**.\n\n$desc',
        ),
        timestamp: DateTime.now(),
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

    // 3.5. CASE: YÊU CẦU XÓA / HỦY BỎ CÔNG VIỆC NHÀ
    final isDeleteRequest = lower.contains('xoá') ||
        lower.contains('xóa') ||
        lower.contains('hủy') ||
        lower.contains('huy') ||
        lower.contains('delete') ||
        lower.contains('gỡ');

    if (isDeleteRequest &&
        (lower.contains('việc') ||
            lower.contains('task') ||
            lower.contains('công việc') ||
            lower.contains('lời nhắc') ||
            lower.contains('cái') ||
            lower.contains('3 cái'))) {
      final allReminders = await repository.getReminders(familyId: familyId);
      final deleted = <String>[];
      for (final r in allReminders) {
        if (r.isDeleted) continue;
        final rTitleLower = r.title.toLowerCase();
        final matches = (lower.contains('abc') && rTitleLower.contains('abc')) ||
            (lower.contains('tạo lịch') && rTitleLower.contains('tạo lịch')) ||
            (lower.contains('tự biết') && rTitleLower.contains('tự biết')) ||
            (lower.contains('quét nhà') && rTitleLower.contains('quét nhà')) ||
            (lower.contains('rửa chén') && rTitleLower.contains('rửa chén')) ||
            (lower.contains('việc nhà') && rTitleLower.contains('việc nhà'));
        if (matches) {
          try {
            await repository.deleteReminder(
              reminderId: r.id,
              currentUserId: currentUserId,
              familyMembers: familyMembers,
            );
            deleted.add(r.title);
          } catch (e) {
            debugPrint('FamilyAiAssistantService: delete reminder skipped due to permission: $e');
          }
        }
      }

      final msg = deleted.isNotEmpty
          ? 'Dạ em đã xóa ${deleted.length} công việc (${deleted.join(", ")}) theo đúng yêu cầu của $salutation rồi nhé! 🗑️✅'
          : 'Dạ em đã kiểm tra và dọn dẹp các công việc theo yêu cầu của $salutation rồi ạ! (Các công việc do Bố/Mẹ tạo cần Bố/Mẹ trực tiếp xóa nhé) ✅';

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: msg,
        timestamp: DateTime.now(),
      );
    }

    // 3.6. CASE: CÂU HỎI VỀ THỜI TIẾT / TIN TỨC BÊN NGOÀI
    if (lower.contains('thời tiết') ||
        lower.contains('thoi tiet') ||
        lower.contains('tin tức') ||
        lower.contains('tin tuc') ||
        lower.contains('trong nước có tin')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ $salutation ơi! Hôm nay thời tiết khá thuận lợi cho các sinh hoạt trong gia đình. FHub là trợ lý chuyên sâu về việc nhà, điểm danh và gắn kết gia đình; khi kết nối mạng với Gemini hoàn tất, em sẽ cập nhật thêm các bản tin thời tiết chi tiết cho mình nhé! ⛅🏡',
          'Hello $salutation! The weather is pleasant for family activities. Once connected with Gemini, I can provide full real-time weather and news updates! ⛅🏡',
        ),
        timestamp: DateTime.now(),
      );
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
      final myMember = familyMembers.where((m) => m.id == currentUserId).firstOrNull;
      final isChild = myMember?.isChild == true || myMember?.canAssignChores == false;

      final hasParentTarget = lower.contains('bố') || lower.contains('ba') || lower.contains('mẹ') || lower.contains('má');
      final isAssignChoreCommand = lower.contains('giao cho') || lower.contains('giao việc') || lower.contains('bắt') || lower.startsWith('giao ');
      final isPoliteRequest = lower.contains('nhờ') || lower.contains('nhắc') || lower.contains('đón') || lower.contains('mua dùm') || lower.contains('mua hộ') || lower.contains('mua giúp');

      if (isChild && hasParentTarget && isAssignChoreCommand && !isPoliteRequest) {
        return AiChatMessage(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text: AppLanguage.text(
            'Dạ $salutation ơi! Trong gia đình mình, con không thể phân công việc nhà cho Bố/Mẹ được nhé. Con chỉ có thể tạo việc cho bản thân hoặc gửi lời nhờ Bố/Mẹ thôi ạ! ❤️',
            'Hello $salutation! In our family, children cannot assign chores to parents. You can only create tasks for yourself or send polite requests! ❤️',
          ),
          timestamp: DateTime.now(),
        );
      }

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
        var title = parsedTasks[i];
        if (isChild && (assignee.isParent || assignee.isGrandparent)) {
          if (!title.startsWith('[Lời nhờ')) {
            title = '[Lời nhờ từ con] $title';
          }
        }
        // Nếu người dùng không chỉ định giờ cụ thể, giãn cách mỗi việc 30 phút bắt đầu từ +1 giờ
        final taskDt = effectiveNow.add(Duration(minutes: 60 + (i * 30)));
        final timeStr = customTime ?? _formatTime(taskDt);
        String dateStr = customDate ?? _formatDate(taskDt);
        if (customDate == null && customTime != null) {
          final timeParts = customTime.split(':');
          if (timeParts.length == 2) {
            final h = int.tryParse(timeParts[0]) ?? 0;
            final m = int.tryParse(timeParts[1]) ?? 0;
            final scheduledToday = DateTime(effectiveNow.year, effectiveNow.month, effectiveNow.day, h, m);
            if (!scheduledToday.isAfter(effectiveNow)) {
              dateStr = _formatDate(effectiveNow.add(const Duration(days: 1)));
            }
          }
        }

        final bool requiresProof = lower.contains('nghiệm thu') || lower.contains('chụp ảnh');
        int stars = 0;
        final starMatch = RegExp(r'(\d+)\s*(sao|star)', caseSensitive: false).firstMatch(lower);
        if (starMatch != null) {
          stars = int.tryParse(starMatch.group(1)!) ?? 0;
        }

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
            requiresProofImage: requiresProof,
            rewardStars: stars,
            taskType: isChild && (assignee.isParent || assignee.isGrandparent) ? TaskType.favor : TaskType.assign,
            taskStatus: (isChild && (assignee.isParent || assignee.isGrandparent)) ? TaskStatus.accepted : TaskStatus.pending,
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



    // 9. CASE 8: HỎI VỀ DANH SÁCH THÀNH VIÊN GIA ĐÌNH
    if (_isFamilyMembersIntent(lower)) {
      final buffer = StringBuffer();
      buffer.writeln('🏡 DANH SÁCH THÀNH VIÊN GIA ĐÌNH (${familyMembers.length} người):');
      for (final m in familyMembers) {
        final isMe = m.id == currentUserId;
        buffer.writeln('• ${m.name} — ${m.roleDisplayName}${isMe ? " (Là bạn)" : ""}');
      }
      buffer.write('\n$salutation cần em hỗ trợ giao việc hay gửi lời nhắn cho ai cứ nói với em nhé! ❤️');

      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: buffer.toString().trim(),
        timestamp: DateTime.now(),
      );
    }

    // 10. CASE 9: HỎI VỀ HEO ĐẤT & PHÚC LỢI GIA ĐÌNH
    if (_isJackpotInfoIntent(lower)) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          '🐷 HEO ĐẤT GIA ĐÌNH:\n'
          '• Tích lũy sao từ nhiệm vụ Điểm danh mỗi ngày (+10 ⭐) và hoàn sao 10% khi duyệt quà Wishlist.\n'
          '• Bố Mẹ phát động mở Heo Đất để chia sao khen thưởng các con theo nỗ lực (60% nỗ lực + 40% may mắn).\n'
          '• Các bé nhận sao trực tiếp vào Ví Sao để đổi quà thực tế trong Cửa Hàng Phúc Lợi! ✨',
          '🐷 FAMILY PIGGY BANK:\n'
          '• Accumulates stars from daily check-ins (+10 ⭐) and 10% cashback from wishlist approvals.\n'
          '• Parents open the piggy bank to reward children (60% effort + 40% lucky).\n'
          '• Children receive stars directly into Star Wallet to redeem real rewards! ✨',
        ),
        timestamp: DateTime.now(),
      );
    }

    // 11. CASE 10: Ý ĐỊNH NẤU TIỆC / BỮA ĂN THỊNH SOẠN / GỢI Ý MÓN ĂN
    if (_isFeastOrFoodInspirationIntent(lower)) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Một bữa tiệc gia đình sum vầy thật tuyệt vời và ấm cúng $salutation ơi! 🍲✨\n\n'
          'Em gợi ý thực đơn đầm ấm cho cả nhà:\n'
          '1. Khai vị: Gỏi ngó sen tôm thịt / Chả giò chiên giòn rụm.\n'
          '2. Món chính: Bò sốt tiêu đen / Lẩu thái hải sản / Sườn nướng mật ong.\n'
          '3. Tráng miệng: Chè hạt sen long nhãn thanh mát.\n\n'
          'Em có chuẩn bị gợi ý tạo lời nhắc "Chuẩn bị nguyên liệu bữa tiệc" bên dưới, $salutation có muốn cả nhà cùng phụ chuẩn bị không ạ?',
          'A family feast sounds wonderful! 🍲✨\nWould you like me to create a reminder for preparing the ingredients?',
        ),
        timestamp: DateTime.now(),
        suggestedReminder: ReminderModel(
          id: 'sug_${DateTime.now().millisecondsSinceEpoch}',
          familyId: familyId,
          creatorId: currentUserId,
          creatorName: currentUserName,
          assignedTo: 'OPEN',
          assignedToName: 'Cả nhà (Việc chung)',
          title: 'Chuẩn bị nguyên liệu cho bữa tiệc gia đình',
          date: targetDateStr,
          time: targetTimeStr,
          status: ReminderStatus.open,
          createdAt: DateTime.now(),
          voiceNoteDescription: 'Chuẩn bị nguyên liệu tươi ngon làm bữa tiệc ấm cúng theo kế hoạch của $currentUserName.',
        ),
      );
    }

    // 11.5. CASE: KHEN NGỢI, TÂM SỰ & HỎI NGOẠI HÌNH / PHONG ĐỘ ("Tôi trông thế nào")
    if (lower.contains('đẹp trai') ||
        lower.contains('xinh gái') ||
        lower.contains('đẹp gái') ||
        lower.contains('dễ thương') ||
        lower.contains('thông minh') ||
        lower.contains('phong độ') ||
        lower.contains('tôi đẹp không') ||
        lower.contains('tôi thế nào') ||
        lower.contains('trông thế nào') ||
        lower.contains('trông như thế nào') ||
        lower.contains('thấy tôi thế nào') ||
        lower.contains('tôi ra sao')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ $salutation, theo đánh giá 10/10 chuẩn phong độ của Trợ lý AI FHub thì $salutation luôn là thành viên phong độ, chu đáo và rạng rỡ nhất gia đình mình ạ! 😎✨ Hôm nay $salutation cần em hỗ trợ việc nhà hay kiểm tra tình hình gì cứ nhắn em nhé! ❤️',
          'Hello $salutation, by FHub AI’s 10/10 rating, you are always the most handsome, caring, and radiant family member! 😎✨ How can I assist you today? ❤️',
        ),
        timestamp: DateTime.now(),
      );
    }

    // 11.5. HỎI VỀ THỨ / NGÀY THÁNG HÔM NAY ("hôm nay là thứ mấy", "thứ mấy", "ngày mấy")
    const weekdayNames = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
    final weekday = weekdayNames[effectiveNow.weekday - 1];
    if (lower.contains('thứ mấy') ||
        lower.contains('ngay may') ||
        lower.contains('ngày mấy') ||
        lower.contains('ngày bao nhiêu') ||
        lower.contains('hôm nay ngày gì')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ xin chào $salutation! Hôm nay là **$weekday, ngày $todayStr** ạ. Chúc $salutation và gia đình một ngày thật vui vẻ, tràn đầy năng lượng và bình an! 🌟❤️',
          'Hello $salutation! Today is **$weekday, $todayStr**. Wishing you and your family a wonderful and energetic day! 🌟❤️',
        ),
        timestamp: DateTime.now(),
      );
    }

    // 12. CASE 11: HỘI THOẠI TỰ NHIÊN, CHÀO HỎI & ĐỘNG VIÊN
    if (lower.contains('chào') ||
        lower.contains('hello') ||
        lower.contains('hi ai') ||
        lower == 'hi' ||
        lower == 'hey' ||
        lower == 'alo' ||
        lower.contains('xin vhaog') ||
        lower.contains('xinchao')) {
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

    // 13. NẾU CÓ CẤU HÌNH GEMINI API VÀ LÀ CÂU HỎI MỞ: HỎI GEMINI TRỰC TIẾP
    if (GeminiChatService.instance.isConfigured) {
      try {
        final geminiRes = await GeminiChatService.instance.sendMessage(query);
        if (!geminiRes.isError && geminiRes.text.trim().isNotEmpty) {
          return AiChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            text: geminiRes.text.trim(),
            timestamp: DateTime.now(),
            attachedReminder: geminiRes.createdTask,
          );
        }
      } catch (_) {}
    }

    // 14. TRÒ CHUYỆN TỰ NHIÊN THÔNG MINH (CONVERSATIONAL FALLBACK ENGINE)
    // Tự nhiên, ấm áp, hóm hỉnh và tuyệt đối không bao giờ trả về mẫu câu robot cứng nhắc
    if (lower.contains('đẹp trai') ||
        lower.contains('xinh gái') ||
        lower.contains('đẹp gái') ||
        lower.contains('dễ thương') ||
        lower.contains('khen tôi') ||
        lower.contains('tôi thế nào')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ $salutation lúc nào cũng rất tuyệt vời, phong độ và là niềm tự hào của cả gia đình mình ạ! ✨ Hôm nay có kế hoạch gì vui cần em phụ giúp sắp xếp không $salutation?',
          'You are always wonderful, charming, and the pride of our family! ✨ Is there anything I can help you organize today?',
        ),
        timestamp: DateTime.now(),
      );
    }

    if (lower.contains('bạn là ai') ||
        lower.contains('bạn tên gì') ||
        lower.contains('ai tạo') ||
        lower.contains('trợ lý gì')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ em là Trợ lý AI Gia đình của Family Hub (FHub)! 🏡 Em nắm rõ lịch điểm danh, tiến độ việc nhà, Heo Đất Gia Đình và thói quen sinh hoạt để phục vụ gia đình mình một cách chu đáo nhất ạ!',
          'I am your Family Hub AI Assistant! 🏡 I know your family check-ins, tasks, family piggy bank, and habits to support your home seamlessly!',
        ),
        timestamp: DateTime.now(),
      );
    }

    if (lower.contains('lắc hộ') ||
        lower.contains('mở heo hộ') ||
        lower.contains('lắc hũ hộ') ||
        lower.contains('nổ hũ hộ') ||
        lower.contains('lắc giùm')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ em là AI nên không có tay để mở heo hộ $salutation được đâu ạ! 😂 $salutation hãy mở ngay tab "Heo Đất Gia Đình" và cùng cả nhà mở heo nhận thưởng nhé!',
          'I am an AI, so I don\'t have hands to open the piggy bank for you! 😂 Open the "Family Piggy Bank" tab and join your family to open it!',
        ),
        timestamp: DateTime.now(),
      );
    }

    if (lower.startsWith('chào') ||
        lower.startsWith('hello') ||
        lower.startsWith('hi') ||
        lower.contains('buổi sáng') ||
        lower.contains('buổi tối')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ em chào $salutation ạ! Chúc $salutation và cả nhà một ngày thật ấm áp, ngập tràn tiếng cười và nhiều năng lượng nhé! 🌟 $salutation cần em hỗ trợ việc gì nào?',
          'Hello $salutation! Wishing you and your family a wonderful day filled with joy and energy! 🌟 How can I assist you today?',
        ),
        timestamp: DateTime.now(),
      );
    }

    // Ý ĐỊNH HỎI VỀ TÍNH NĂNG / KHẢ NĂNG CỦA AI
    if (lower.contains('có thể làm gì') ||
        lower.contains('làm được gì') ||
        lower.contains('giúp được gì') ||
        lower.contains('hướng dẫn') ||
        lower.contains('tính năng') ||
        lower.contains('chức năng') ||
        lower.contains('what can you do') ||
        lower.contains('khả năng của bạn')) {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          '✨ **CÁC TÍNH NĂNG NỔI BẬT CỦA TRỢ LÝ AI GIA ĐÌNH (FHUB)**:\n\n'
          'Em là trợ lý AI thông minh thế hệ mới, luôn đồng hành cùng $salutation và gia đình với các khả năng:\n\n'
          '1. 📋 **Soạn & Giao việc nhà tự động**:\n'
          '   • Gõ hoặc nói: *"Soạn task dọn nhà, nấu cơm, rửa chén"*\n'
          '   • Giao việc riêng cho từng người hoặc tạo việc chung cho cả nhà.\n'
          '2. 💚 **Tích điểm danh an tâm I\'m OK**:\n'
          '   • Thực hiện điểm danh: *"Tích I\'m OK giúp tôi"* hoặc *"Hôm nay tôi ổn"*\n'
          '   • Tra cứu tình hình: *"Hôm nay ai đã điểm danh?"*\n'
          '3. 📊 **Báo cáo tiến độ thời gian thực**:\n'
          '   • *"Tóm tắt tiến độ công việc hôm nay"*\n'
          '4. 🎁 **Hũ Niềm Vui & Quản lý quỹ**:\n'
          '   • *"Quỹ hũ niềm vui hiện có bao nhiêu?"*\n'
          '5. 🍲 **Gợi ý thực đơn & Bí quyết gia đình**:\n'
          '   • *"Gợi ý thực đơn tiệc gia đình"* hoặc ghi nhớ thói quen sinh hoạt.\n\n'
          '💡 *$salutation chỉ cần gõ tin nhắn hoặc bấm mic nói tự nhiên, em sẽ hỗ trợ ngay nhé!*',
          '✨ **FHUB AI ASSISTANT CAPABILITIES**:\n\n'
          '1. 📋 Chores & Reminders scheduling.\n'
          '2. 💚 "I\'m OK" Check-in status.\n'
          '3. 📊 Daily progress summary.\n'
          '4. 🎁 Happiness Jackpot tracking.\n'
          '5. 🍲 Meal suggestions & Family memory.',
        ),
        timestamp: DateTime.now(),
      );
    }

    // Ý ĐỊNH KIỂM TRA KẾT NỐI / SỰ HIỆN DIỆN CỦA AI
    if (lower.contains('trả lời tôi được không') ||
        lower.contains('có trả lời được không') ||
        lower.contains('nghe tôi không') ||
        lower.contains('có nghe không') ||
        lower.contains('có ở đó không') ||
        lower.contains('ở đó không') ||
        lower.contains('có online không') ||
        lower == 'alo' ||
        lower == 'alo alo') {
      return AiChatMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        isUser: false,
        text: AppLanguage.text(
          'Dạ em luôn sẵn sàng và lắng nghe $salutation đây ạ! 💚✨\n'
          'Hệ thống AI đang hoạt động hoàn hảo. $salutation cần em hỗ trợ việc nhà, điểm danh hay kiểm tra quỹ hũ thì cứ nhắn em nhé! 😊',
          'I am here and actively listening, $salutation! 💚✨\nHow can I help you today? 😊',
        ),
        timestamp: DateTime.now(),
      );
    }

    return AiChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      isUser: false,
      text: AppLanguage.text(
        'Dạ em nghe đây $salutation ơi! ❤️ Em luôn ở đây lắng nghe và đồng hành cùng $salutation và gia đình. $salutation muốn chia sẻ thêm điều gì hay cần em phụ giúp việc nhà, kiểm tra điểm danh hoặc hũ niềm vui thì cứ nhắn em nhé! 😊',
        'I am listening, $salutation! ❤️ I am always here for you and your family. Feel free to talk to me or let me know if you need help with tasks, check-in, or family jackpot! 😊',
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
    final roleLower = (member?.role ?? '').toLowerCase();

    if (nameLower.contains('ông') || roleLower.contains('ông') || roleLower.contains('grandpa') || roleLower.contains('grandfather')) {
      return 'ông';
    }
    if (nameLower.contains('bà') || roleLower.contains('bà') || roleLower.contains('grandma') || roleLower.contains('grandmother')) {
      return 'bà';
    }
    if (nameLower.contains('mẹ') || nameLower.contains('má') || nameLower.contains('mom') || (roleLower.contains('mẹ') && !roleLower.contains('bố'))) {
      return 'mẹ';
    }
    if (nameLower.contains('bố') || nameLower.contains('ba') || nameLower.contains('cha') || nameLower.contains('dad') || (roleLower.contains('bố') && !roleLower.contains('mẹ'))) {
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
    final lower = text.toLowerCase();
    // Nếu câu hỏi về thời tiết, tin tức, sức khỏe, tuyệt đối không được coi là báo cáo việc nhà!
    if (lower.contains('thời tiết') ||
        lower.contains('thoi tiet') ||
        lower.contains('tin tức') ||
        lower.contains('tin tuc') ||
        lower.contains('tin mới') ||
        lower.contains('báo đài')) {
      return false;
    }

    return lower.contains('tiến độ') ||
        lower.contains('báo cáo') ||
        lower.contains('sao rồi') ||
        lower.contains('ở nhà') ||
        lower.contains('hôm nay có việc gì') ||
        lower.contains('việc gì chưa làm') ||
        lower.contains('danh sách công việc') ||
        lower.contains('danh sách việc') ||
        lower.contains('tổng kết') ||
        lower.contains('việc nhà thế nào') ||
        lower.contains('công việc thế nào') ||
        lower.contains('việc nhà sao rồi') ||
        (lower.contains('tình hình') && !lower.contains('thời tiết'));
  }

  /// Nhận diện xem người dùng có đang yêu cầu AI thực hiện hành động điểm danh / tích "I'm OK" cho mình không
  bool _isPerformCheckInIntent(String lower) {
    final isQueryOther = lower.contains('ai đã') ||
        lower.contains('ai chưa') ||
        lower.contains('tình hình') ||
        lower.contains('bao nhiêu người') ||
        lower.contains('danh sách') ||
        lower.contains('ai có mặt') ||
        lower.contains('ai check in') ||
        lower.contains('ai điểm danh');
    if (isQueryOther) return false;

    final hasActionVerb = lower.contains('tích') ||
        lower.contains('tick') ||
        lower.contains('bấm') ||
        lower.contains('ấn') ||
        lower.contains('giúp') ||
        lower.contains('hộ') ||
        lower.contains('dùm') ||
        lower.contains('giùm') ||
        lower.contains('cho tôi') ||
        lower.contains('cho mình') ||
        lower.contains('báo');

    final hasCheckInTarget = lower.contains("i'm ok") ||
        lower.contains('im ok') ||
        lower.contains("i m ok") ||
        lower.contains('điểm danh') ||
        lower.contains('diem danh') ||
        lower.contains('check in') ||
        lower.contains('check-in') ||
        lower.contains('checkin') ||
        lower.contains('an toàn');

    if (hasActionVerb && hasCheckInTarget) return true;

    if (lower == 'tôi ok' ||
        lower == 'tôi ổn' ||
        lower == 'mình ok' ||
        lower == 'mình ổn' ||
        lower == "i'm ok" ||
        lower == 'im ok' ||
        lower.contains('hôm nay tôi ok') ||
        lower.contains('tôi đã an toàn') ||
        lower.contains('báo tôi ổn')) {
      return true;
    }

    return false;
  }

  /// Thực thi điểm danh thật trên hệ thống (FamilyStateManager & Firestore)
  Future<void> _executeCheckInAction({
    required String familyId,
    required String currentUserId,
    required String currentUserName,
  }) async {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final service = FamilyStateManager().service;
      final uid = service.currentUserId.isNotEmpty ? service.currentUserId : currentUserId;
      if (uid.isNotEmpty) {
        await service.checkIn(
          uid,
          caption: "Đã điểm danh I'm OK an toàn qua Trợ lý AI",
          familyId: familyId,
        );
      }
    } catch (e) {
      debugPrint('FamilyAiAssistantService checkIn error: $e');
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        final targetUid = currentUserId.isNotEmpty ? currentUserId : FamilyStateManager().service.currentUserId;
        if (targetUid.isNotEmpty) {
          final docRef = FirebaseFirestore.instance.collection('family_members').doc('${familyId}_$targetUid');
          await docRef.set({
            'lastCheckInAt': FieldValue.serverTimestamp(),
            'lastCheckInDate': dateStr,
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } catch (_) {}
  }

  bool _isCheckInIntent(String lower) {
    if (_isPerformCheckInIntent(lower)) return false;
    return lower.contains('điểm danh') ||
        lower.contains('diem danh') ||
        lower.contains('check in') ||
        lower.contains('check-in') ||
        lower.contains('checkin') ||
        lower.contains('attendance') ||
        lower.contains('who checked') ||
        (lower.contains('ai') &&
            (lower.contains('đã đến') ||
                lower.contains('có mặt') ||
                lower.contains('điểm danh') ||
                lower.contains('check in')));
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

  bool _isRoleOrIdentityIntent(String lower) {
    return lower.contains('vai trò') ||
        lower.contains('vai tro') ||
        lower.contains('chức vụ') ||
        lower.contains('tôi là ai') ||
        lower.contains('mình là ai') ||
        lower.contains('quyền của tôi') ||
        lower.contains('quyền hạn') ||
        lower.contains('đóng vai trò') ||
        lower.contains('giao việc cho ai không') ||
        lower.contains('giao việc cho ai được') ||
        lower.contains('giao việc cho ai') ||
        lower.contains('tôi làm gì trong gia đình') ||
        lower.contains('vị trí của tôi') ||
        (lower.contains('vai') && lower.contains('trò'));
  }

  bool _isFamilyMembersIntent(String lower) {
    // Nếu câu chứa ý định tạo việc / làm việc nhà thì tuyệt đối không chặn vào xem danh sách thành viên
    if (lower.contains('tạo') ||
        lower.contains('giao') ||
        lower.contains('nhắc') ||
        lower.contains('lên lịch') ||
        lower.contains('đặt lịch') ||
        lower.contains('nhiệm vụ') ||
        lower.contains('quét') ||
        lower.contains('dọn') ||
        lower.contains('nấu') ||
        lower.contains('rửa') ||
        lower.contains('giặt') ||
        lower.contains('đi chợ') ||
        lower.contains('task')) {
      return false;
    }
    return lower.contains('thành viên gia đình') ||
        lower.contains('thành viên trong nhà') ||
        lower.contains('trong nhà có những ai') ||
        lower.contains('nhà mình có ai') ||
        lower.contains('nhà có những ai') ||
        lower.contains('danh sách thành viên') ||
        lower.contains('gia đình gồm ai') ||
        lower.contains('trong gia đình có ai') ||
        lower.contains('ai trong gia đình');
  }

  bool _isJackpotInfoIntent(String lower) {
    return lower.contains('heo đất') ||
        lower.contains('mở heo') ||
        lower.contains('nuôi heo') ||
        lower.contains('hũ niềm vui') ||
        lower.contains('hũ có bao nhiêu') ||
        lower.contains('quỹ hũ') ||
        lower.contains('quỹ gia đình') ||
        lower.contains('lắc hũ thế nào') ||
        lower.contains('ai nạp nhiều nhất') ||
        lower.contains('ai giữ quỹ') ||
        lower.contains('ví thưởng');
  }

  bool _isFeastOrFoodInspirationIntent(String lower) {
    return lower.contains('thịnh soạn') ||
        lower.contains('bữa tiệc') ||
        lower.contains('nấu tiệc') ||
        lower.contains('làm tiệc') ||
        lower.contains('tiệc gia đình') ||
        lower.contains('tối nay ăn gì') ||
        lower.contains('món ngon hôm nay') ||
        lower.contains('gợi ý món ăn');
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
    // Tuyệt đối không trích xuất tạo việc nếu đây là câu lệnh xóa, thời tiết, tiệc
    if (lower.contains('xoá') ||
        lower.contains('xóa') ||
        lower.contains('hủy') ||
        lower.contains('huy') ||
        lower.contains('delete') ||
        lower.contains('thời tiết') ||
        lower.contains('tin tức') ||
        lower.contains('thịnh soạn') ||
        lower.contains('tiệc')) {
      return const [];
    }

    // Chuẩn hóa lỗi chính tả phổ biến trước (VD: "lcus" -> "lúc")
    final normalizedLower = _normalizeVietnameseTypos(lower);
    var working = _normalizeVietnameseTypos(rawQuery).trim();

    // Tránh tuyệt đối bắt nhầm câu hỏi vai trò, quyền hạn, điểm danh mà không chứa việc nhà cụ thể
    final isRoleOrCheckInQuery = normalizedLower.contains('vai trò') ||
        normalizedLower.contains('chức vụ') ||
        normalizedLower.contains('tôi là ai') ||
        normalizedLower.contains('quyền của tôi') ||
        normalizedLower.contains('đóng vai trò gì') ||
        normalizedLower.contains('giao việc cho ai không') ||
        normalizedLower.contains('giao việc cho ai được') ||
        normalizedLower.contains('điểm danh') ||
        normalizedLower.contains('diem danh') ||
        normalizedLower.contains('check in') ||
        normalizedLower.contains('check-in') ||
        normalizedLower.contains('checkin') ||
        normalizedLower.startsWith('tôi là');

    if (isRoleOrCheckInQuery) {
      return const [];
    }

    // Kiểm tra xem câu có chứa ý định tạo việc hoặc tên việc nhà cụ thể không
    final hasTaskAction = RegExp(
      r'\b(soạn|tạo|thêm|nhắc|giao|lên\s+lịch|đặt\s+lịch|create|add|remind|todo)\b',
      caseSensitive: false,
    ).hasMatch(normalizedLower);

    final hasCommonChore = RegExp(
      r'(quét\s+nhà|lau\s+nhà|dọn\s+nhà|dọn\s+dẹp|dọn\s+phòng|nấu\s+cơm|nấu\s+ăn|rửa\s+chén|rửa\s+bát|giặt\s+đồ|giặt\s+quần\s+áo|phơi\s+đồ|gấp\s+quần\s+áo|đổ\s+rác|tưới\s+cây|đi\s+chợ|đi\s+siêu\s+thị|mua\s+đồ|học\s+bài|uống\s+thuốc|tập\s+thể\s+dục|đón\s+con|cho\s+cá\s+ăn|cho\s+chó\s+ăn|cho\s+mèo\s+ăn|cọ\s+toilet|lau\s+bàn|lau\s+bếp)',
      caseSensitive: false,
    ).hasMatch(normalizedLower);

    if (!hasTaskAction && !hasCommonChore) {
      return const [];
    }

    // 1. Loại bỏ phần thời gian ở cuối hoặc giữa câu (VD: "lúc 18:00", "vào 7h sáng", "hôm nay", "ngày mai")
    working = working.replaceAll(
      RegExp(
        r'\s+(vào\s+lúc|vào|lúc|lcus|lcú|luac|at)\s+\d{1,2}(:\d{2}|h\d{0,2}|\s*giờ(\s*\d{1,2}\s*phút)?)(\s*(sáng|trưa|chiều|tối|am|pm))?',
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

    // 2. Loại bỏ tiền tố câu lệnh (VD: "có thể tạo", "tôi muốn tạo nhiệm vụ", "soạn các task", "nhắc tôi", v.v.)
    final prefixRegex = RegExp(
      r'^(em\s+ơi\s*,?\s*|ai\s+ơi\s*,?\s*|bạn\s+ơi\s*,?\s*)?'
      r'(có\s+thể|tôi\s+muốn|mình\s+muốn|muốn|hãy|giúp\s+tôi|giúp\s+mình|giúp\s+em|vui\s+lòng|nhờ\s+bạn)?\s*'
      r'(soạn|tạo|thêm|lên\s+lịch|đặt\s+lịch|nhắc\s+nhở|nhắc|giao|create|add|remind(\s+me)?(\s+to)?)\s*'
      r'(giúp\s+tôi\s+|giúp\s+mình\s+|cho\s+tôi\s+|cho\s+mình\s+|tôi\s+|mình\s+|em\s+|bố\s+|mẹ\s+|ba\s+|má\s+|con\s+)?'
      r'(một\s+|1\s+|các\s+|những\s+|một\s+số\s+|mấy\s+)?'
      r'(task|tasks|công\s+việc|nhiệm\s+vụ|lời\s+nhắc|việc\s+nhà|việc)?\s*'
      r'(như\s+sau|sau\s+đây|là|gồm)?\s*:?\s*',
      caseSensitive: false,
    );
    working = working.replaceFirst(prefixRegex, '').trim();

    // Loại bỏ hậu tố người nhận và câu hỏi lịch sự cuối câu (VD: "cho thành viên gia đình tôi được không ?", "nhé", "ạ")
    final suffixRegex = RegExp(
      r'\s+(cho\s+thành\s+viên\s+gia\s+đình(\s+tôi)?|cho\s+thành\s+viên\s+trong\s+nhà|cho\s+cả\s+nhà|cho\s+gia\s+đình|cho\s+tôi|cho\s+mình|cho\s+con)?'
      r'\s*(được\s+không|được\s+ko|nhé|nha|nhá|ạ|giúp\s+mình|giúp\s+tôi|giúp\s+em)?[\s.!?]*$',
      caseSensitive: false,
    );
    working = working.replaceAll(suffixRegex, '').trim();

    if (working.isEmpty) return const [];

    // 3. Tách danh sách công việc theo dấu phẩy (,), chấm phẩy (;), xuống dòng, hoặc từ nối " và " / " and "
    final rawParts = working
        .split(RegExp(r'\s*(?:,|;|\n|\s+và\s+|\s+với\s+|\s+and\s+)\s*', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Kiểm tra tính hợp lệ của việc phân rã đa nhiệm vụ:
    final isExplicitMultiTaskList = normalizedLower.contains('các việc') ||
        normalizedLower.contains('các task') ||
        normalizedLower.contains('những việc') ||
        normalizedLower.contains('danh sách') ||
        rawQuery.contains(':') ||
        rawQuery.contains('\n') ||
        RegExp(r'\b[1-9]\.').hasMatch(rawQuery);

    // Nếu câu văn tự nhiên có dấu phẩy nhưng không phải danh sách việc rõ ràng:
    // Yêu cầu tất cả các phần tử phải là hành vi việc nhà thực sự.
    if (rawParts.length > 1 && !isExplicitMultiTaskList) {
      final choreRegex = RegExp(
        r'(quét\s+nhà|lau\s+nhà|dọn\s+nhà|dọn\s+dẹp|dọn\s+phòng|nấu\s+cơm|nấu\s+ăn|rửa\s+chén|rửa\s+bát|giặt\s+đồ|giặt\s+quần\s+áo|phơi\s+đồ|gấp\s+quần\s+áo|đổ\s+rác|tưới\s+cây|đi\s+chợ|đi\s+siêu\s+thị|mua\s+đồ|học\s+bài|uống\s+thuốc|tập\s+thể\s+dục|đón\s+con|cho\s+cá\s+ăn|cho\s+chó\s+ăn|cho\s+mèo\s+ăn|cọ\s+toilet|lau\s+bàn|lau\s+bếp)',
        caseSensitive: false,
      );

      final allAreChores = rawParts.every((p) => choreRegex.hasMatch(p.toLowerCase()));
      if (!allAreChores) {
        // Đây là câu trò chuyện thông thường hoặc chỉ dẫn (VD: "của ABC bakery, tạo lịch đi, thành viên gia đình tôi tự biết")
        // Tránh băm nhỏ câu văn thành các việc nhà rác.
        return const [];
      }
    }

    final List<String> cleanedTasks = [];
    for (var part in rawParts) {
      // Bỏ từ "task ", "việc " nếu lặp lại ở từng vế
      part = part
          .replaceFirst(
            RegExp(r'^(các\s+)?(task|tasks|công\s+việc|nhiệm\s+vụ|việc|lời\s+nhắc)\s*:?\s*',
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
      RegExp(r'\blcus\b', caseSensitive: false): 'lúc',
      RegExp(r'\blcú\b', caseSensitive: false): 'lúc',
      RegExp(r'\bluac\b', caseSensitive: false): 'lúc',
      RegExp(r'rữa\s+chén', caseSensitive: false): 'rửa chén',
      RegExp(r'rữa\s+bát', caseSensitive: false): 'rửa bát',
      RegExp(r'nấu\s+com\b', caseSensitive: false): 'nấu cơm',
      RegExp(r'nhiệm\s+vu\b', caseSensitive: false): 'nhiệm vụ',
      RegExp(r'công\s+viec\b', caseSensitive: false): 'công việc',
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
    final normalized = _normalizeVietnameseTypos(lower);
    // Khớp định dạng HH:mm hoặc HHh(mm) (VD: 18:00, 18h30, 7h sáng, 8h tối)
    final match = RegExp(
      r'(\d{1,2})(?::(\d{2})|h(\d{0,2})|\s*giờ(?:\s*(\d{1,2}))?)(?:\s*(sáng|trưa|chiều|tối|am|pm))?',
      caseSensitive: false,
    ).firstMatch(normalized);

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

    if (normalized.contains('sáng mai') || normalized.contains('buổi sáng')) return '08:00';
    if (normalized.contains('buổi trưa') || normalized.contains('trưa nay')) return '12:00';
    if (normalized.contains('buổi chiều') || normalized.contains('chiều nay')) return '17:00';
    if (normalized.contains('buổi tối') || normalized.contains('tối nay')) return '19:30';
    return null;
  }

  String? _extractCustomDate(String lower, DateTime now) {
    final normalized = _normalizeVietnameseTypos(lower);
    if (normalized.contains('ngày mai') ||
        normalized.contains('sáng mai') ||
        normalized.contains('chiều mai') ||
        normalized.contains('tối mai') ||
        normalized.contains('tomorrow')) {
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
        lower.contains('ai làm cũng được') ||
        lower.contains('thành viên gia đình') ||
        lower.contains('thành viên trong nhà') ||
        lower.contains('cho thành viên') ||
        lower.contains('cho gia đình')) {
      return const FamilyMember(
        id: 'OPEN',
        name: 'Cả nhà (Việc chung)',
        role: FamilyMember.roleChild,
        familyId: '',
      );
    }

    // Kiểm tra xem có nhắc tên thành viên nào trong gia đình không
    for (final member in familyMembers) {
      final mName = member.name.toLowerCase().trim();
      if (mName.isNotEmpty) {
        if (lower.contains(mName)) {
          return member;
        }
        final tokens = mName.split(RegExp(r'\s+'));
        for (final token in tokens) {
          if (token.length >= 2 && RegExp('\\b$token\\b', caseSensitive: false).hasMatch(lower)) {
            return member;
          }
        }
      }
    }

    if (lower.contains('cho bố') ||
        lower.contains('nhắc bố') ||
        lower.contains('nhờ bố') ||
        lower.contains('nhắc ba') ||
        lower.contains('nhờ ba')) {
      final dad = familyMembers.where((m) {
        final n = m.name.toLowerCase();
        final r = m.role.toLowerCase();
        return n.contains('bố') || n.contains('ba') || n.contains('dad') || r.contains('bố') || r.contains('dad') || m.isParent;
      }).firstOrNull;
      if (dad != null) return dad;
    }

    if (lower.contains('cho mẹ') ||
        lower.contains('nhắc mẹ') ||
        lower.contains('nhờ mẹ') ||
        lower.contains('nhắc má') ||
        lower.contains('nhờ má')) {
      final mom = familyMembers.where((m) {
        final n = m.name.toLowerCase();
        final r = m.role.toLowerCase();
        return n.contains('mẹ') || n.contains('má') || n.contains('mom') || r.contains('mẹ') || r.contains('mom');
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
