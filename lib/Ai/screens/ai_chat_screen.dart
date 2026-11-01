import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../Long/services/family_data_service.dart';
import '../../Vinh/models/family_member.dart';
import '../../Vinh/screens/family_ai_chat_screen.dart';
import '../../Vinh/services/reminder_repository.dart';

/// Màn hình điều phối Trợ lý AI Gia đình dùng chung cho toàn bộ các tab (Home, Family, Profile, Reminders)
class AiChatScreen extends StatefulWidget {
  final String? familyId;

  const AiChatScreen({super.key, this.familyId});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  bool _isLoading = true;
  String _familyId = 'f1';
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
      final dataService = FamilyDataService();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _currentUserId = user.uid;
        _currentUserName =
            (user.displayName != null && user.displayName!.trim().isNotEmpty)
                ? user.displayName!.trim()
                : (user.email?.split('@').first ?? 'Bạn');
      }

      final myFamilies = await dataService.getMyFamilies();
      String resolvedFamId = widget.familyId ?? dataService.selectedFamilyId ?? '';
      if (resolvedFamId.isEmpty && myFamilies.isNotEmpty) {
        resolvedFamId = myFamilies.first.id;
      }
      if (resolvedFamId.isNotEmpty) {
        _familyId = resolvedFamId;
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

    return FamilyAiChatScreen(
      familyId: _familyId,
      currentUserId: _currentUserId,
      currentUserName: _currentUserName,
      familyMembers: _familyMembers,
      repository: _repository,
    );
  }
}
