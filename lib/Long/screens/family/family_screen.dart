import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/supabase_service.dart';
import '../../models/family_model.dart';
import '../../models/family_member_model.dart';
import '../../models/user_model.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/family_member_tile.dart';
import 'create_family_screen.dart';
import 'join_family_screen.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _supabaseService = SupabaseService();
  final bool _mockHasFamily = true;

  late Future<Map<String, dynamic>> _familyDataFuture;

  @override
  void initState() {
    super.initState();
    if (_mockHasFamily) {
      _loadData();
    }
  }

  void _loadData() {
    _familyDataFuture = _fetchFamilyData();
  }

  Future<Map<String, dynamic>> _fetchFamilyData() async {
    final family = await _supabaseService.getCurrentFamily();
    final members = await _supabaseService.getFamilyMembers();
    return {
      'family': family,
      'members': members,
    };
  }

  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Mã $code đã được sao chép!')));
  }

  @override
  Widget build(BuildContext context) {
    if (!_mockHasFamily) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Tổ Ấm Yêu Thương'),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.family_restroom,
                size: 80,
                color: Color(0xFF005F50),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Family Hub',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF151D1B),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "You aren't in a family yet. Create one or join an existing family to get started.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Color(0xFF3E4946)),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF005F50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateFamilyScreen(),
                    ),
                  );
                },
                child: const Text(
                  'Create a Family',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  foregroundColor: const Color(0xFF005F50),
                  side: const BorderSide(color: Color(0xFF005F50)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JoinFamilyScreen()),
                  );
                },
                child: const Text(
                  'Join a Family',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(title: 'Tổ Ấm Yêu Thương'),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _familyDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          final FamilyModel family = data['family'];
          final List<FamilyMemberModel> members = data['members'];

          final currentMember = members.firstWhere(
            (m) => m.user.id == _supabaseService.currentUserId,
            orElse: () => FamilyMemberModel(
              familyId: family.id,
              user: members.isNotEmpty ? members.first.user : UserModel(id: '11111111-1111-1111-1111-111111111111', name: '?', email: '?'),
              role: Role.member,
            ),
          );
          final isOwner = currentMember.role == Role.owner;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFBDC9C4).withOpacity(0.6),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120D7A68),
                        offset: Offset(0, 10),
                        blurRadius: 24,
                        spreadRadius: -4,
                      ),
                      BoxShadow(
                        color: Color(0x0DF49D37),
                        offset: Offset(0, 4),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.cottage,
                                color: Color(0xFF0D7A68),
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                family.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF151D1B),
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => _copyToClipboard(family.joinCode),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2EAE7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Text(
                                    'Mã: ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6E7A75),
                                    ),
                                  ),
                                  Text(
                                    family.joinCode,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF005F50),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.content_copy,
                                    size: 14,
                                    color: Color(0xFF005F50),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Thành viên trong tổ ấm (${members.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6E7A75),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...members.map(
                        (member) => FamilyMemberTile(member: member),
                      ),

                      if (isOwner) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(
                                color: Color(0xFFBDC9C4),
                                style: BorderStyle.solid,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              foregroundColor: const Color(0xFF005F50),
                              backgroundColor: const Color(0xFFE7F0EC)
                                  .withOpacity(0.3),
                            ),
                            onPressed: () => _copyToClipboard(family.joinCode),
                            icon: const Icon(Icons.person_add, size: 20),
                            label: const Text(
                              'Thêm thành viên mới',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}
