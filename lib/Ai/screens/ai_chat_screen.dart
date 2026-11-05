import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../Long/services/family_data_service.dart';
import '../../Vinh/models/family_member.dart';
import '../../Vinh/screens/family_ai_chat_screen.dart';
import '../../Vinh/services/reminder_repository.dart';
import '../services/gemini_chat_service.dart';

/// Màn hình điều phối Trợ lý AI Gia đình dùng chung cho toàn bộ các tab (Home, Family, Profile, Reminders)
/// Tự động nạp ngữ cảnh thời gian thực (Vai trò, danh sách thành viên, việc nhà) vào Gemini LLM
class AiChatScreen extends StatefulWidget {
  final String? familyId;

  const AiChatScreen({super.key, this.familyId});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  bool _isLoading = true;
  String _familyId = '';
  String _currentUserId = 'user_current';
  String _currentUserName = 'Bạn';
  List<FamilyMember> _familyMembers = [];
  final ReminderRepository _repository = FirebaseReminderRepository();

  @override
  void initState() {
    super.initState();
    _loadFamilyContext();
  }

  Future<void> _loadFamilyContext() async {
    try {
      final bool hasFirebase = Firebase.apps.isNotEmpty;
      final dataService = FamilyDataService();
      final user = hasFirebase ? FirebaseAuth.instance.currentUser : null;
      if (user != null) {
        _currentUserId = user.uid;
        _currentUserName =
            (user.displayName != null && user.displayName!.trim().isNotEmpty)
                ? user.displayName!.trim()
                : (user.email?.split('@').first ?? 'Bạn');
      }

      final myFamilies = await dataService.getMyFamilies(forceRefresh: true);
      String resolvedFamId = widget.familyId ?? dataService.selectedFamilyId ?? '';
      if (myFamilies.isNotEmpty) {
        if (resolvedFamId.isEmpty ||
            !myFamilies.any((f) => f.id == resolvedFamId)) {
          resolvedFamId = myFamilies.first.id;
        }
        _familyId = resolvedFamId;
      } else if (!hasFirebase || user == null) {
        // Chỉ fallback mock 'f1' khi chạy môi trường test / offline không có Firebase Auth
        _familyId = resolvedFamId.isNotEmpty ? resolvedFamId : 'f1';
      } else {
        // Người dùng thật chưa tham gia gia đình nào -> giữ rỗng để chặn sử dụng AI
        _familyId = '';
      }

      if (_familyId.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      // Đọc tên người dùng từ collection users nếu có
      if (user != null) {
        try {
          final uDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 2));
          if (uDoc.exists && uDoc.data() != null) {
            final name = (uDoc.data()!['name'] ?? uDoc.data()!['displayName'])
                ?.toString()
                .trim();
            if (name != null && name.isNotEmpty) {
              _currentUserName = name;
            }
          }
        } catch (_) {}
      }

      // Đọc danh sách thành viên trong gia đình hiện tại
      final List<FamilyMember> members = [];
      try {
        final snap = await FirebaseFirestore.instance
            .collection('family_members')
            .where('familyId', isEqualTo: _familyId)
            .get()
            .timeout(const Duration(seconds: 3));

        for (final doc in snap.docs) {
          final d = doc.data();
          final status = (d['status'] ?? 'ACTIVE').toString();
          if (status != 'ACTIVE') continue;

          final uid = (d['userId'] ?? d['user_id'] ?? doc.id).toString();
          final role = (d['role'] ?? FamilyMember.roleParent).toString();
          var mName = (d['name'] ?? d['userName'] ?? '').toString().trim();

          if (mName.isEmpty && uid == _currentUserId) {
            mName = _currentUserName;
          }
          if (mName.isEmpty) {
            mName = 'Thành viên';
          }

          members.add(
            FamilyMember(
              id: uid,
              name: mName,
              role: role,
              familyId: _familyId,
            ),
          );
        }
      } catch (_) {}

      if (members.isEmpty) {
        members.add(
          FamilyMember(
            id: _currentUserId,
            name: _currentUserName,
            role: FamilyMember.roleParent,
            familyId: _familyId,
          ),
        );
      }
      _familyMembers = members;

      // Nạp ngữ cảnh vào GeminiChatService thời gian thực
      final myMember = _familyMembers.where((m) => m.id == _currentUserId).firstOrNull;
      final myRole = myMember?.role ?? 'Thành viên';
      final activeFamily = myFamilies.where((f) => f.id == _familyId).firstOrNull;
      final activeFamilyName = activeFamily?.name ?? '';
      unawaited(GeminiChatService.instance.initChat(
        familyId: _familyId,
        familyName: activeFamilyName.isNotEmpty ? activeFamilyName : null,
        userId: _currentUserId,
        userName: _currentUserName,
        userRole: myRole,
      ));
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F8F7),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0D7A68)),
        ),
      );
    }

    return SafeArea(
      top: false,
      bottom: true,
      child: FamilyAiChatScreen(
        familyId: _familyId,
        currentUserId: _currentUserId,
        currentUserName: _currentUserName,
        familyMembers: _familyMembers,
        repository: _repository,
      ),
    );
  }
}
