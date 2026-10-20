import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'Khoa/models/family.dart';
import 'Khoa/screens/create_family_screen.dart';
import 'Khoa/screens/family_setup_screen.dart';
import 'Vinh/models/family_member.dart' as vinh;
import 'Vinh/screens/calendar_page.dart';
import 'Vinh/screens/reminder_list_screen.dart';
import 'Vinh/services/supabase_config.dart';
import 'Vinh/services/supabase_reminder_repository.dart';
import 'firebase_options.dart';

/// Entry point chạy thử trực tiếp chức năng Remind (bỏ qua Login)
/// và đồng thời test cơ chế Tạo/Thiết lập gia đình trong folder Khoa.
///
/// Cách chạy:
///   flutter run -t lib/main_test_reminder.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Khởi tạo Firebase (Auth & Firestore)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ [TestEntry] Firebase initialized successfully.');

    // Tự động đăng nhập ẩn danh nếu chưa đăng nhập, để FamilyService của Khoa
    // không bị lỗi "Chưa đăng nhập" khi người dùng bấm tạo gia đình.
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      try {
        await auth.signInAnonymously();
        debugPrint(
            '✅ [TestEntry] Auto-signed in anonymously: ${auth.currentUser?.uid}');
      } catch (authErr) {
        debugPrint('⚠️ [TestEntry] Anonymous sign in skipped/failed: $authErr');
      }
    }
  } catch (e) {
    debugPrint('⚠️ [TestEntry] Firebase init skipped/error: $e');
  }

  // 2. Khởi tạo Supabase (với fallback offline nếu không có internet)
  try {
    await SupabaseConfig.initialize();
    debugPrint('✅ [TestEntry] Supabase initialized successfully.');
  } catch (e) {
    debugPrint('⚠️ [TestEntry] Supabase init skipped/error: $e');
  }

  runApp(const TestReminderApp());
}

class TestReminderApp extends StatelessWidget {
  const TestReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF005F50);

    return MaterialApp(
      title: 'Test Remind & Family Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Be Vietnam Pro',
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          surface: const Color(0xFFF3FBF8),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3FBF8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEDF5F2),
          elevation: 1,
          shadowColor: Colors.black12,
          foregroundColor: primaryColor,
        ),
      ),
      home: const TestNavigationShell(),
    );
  }
}

class TestNavigationShell extends StatefulWidget {
  const TestNavigationShell({super.key});

  @override
  State<TestNavigationShell> createState() => _TestNavigationShellState();
}

class _TestNavigationShellState extends State<TestNavigationShell> {
  int _currentIndex = 0;
  String _currentFamilyId = 'family_1';
  String _currentFamilyName = 'Gia đình Hạnh Phúc';

  // Danh sách thành viên gia đình mẫu để kiểm thử phân quyền & giao việc
  final List<vinh.FamilyMember> _sampleMembers = const [
    vinh.FamilyMember(
      id: 'user_mom',
      name: 'Mẹ Lan',
      role: vinh.FamilyMember.roleParent,
      familyId: 'family_1',
    ),
    vinh.FamilyMember(
      id: 'user_dad',
      name: 'Bố Hùng',
      role: vinh.FamilyMember.roleParent,
      familyId: 'family_1',
    ),
    vinh.FamilyMember(
      id: 'user_minh',
      name: 'Minh',
      role: vinh.FamilyMember.roleChild,
      familyId: 'family_1',
      rewardStarsTotal: 12,
    ),
    vinh.FamilyMember(
      id: 'user_grandma',
      name: 'Bà Ngoại',
      role: vinh.FamilyMember.roleGrandparent,
      familyId: 'family_1',
    ),
  ];

  late final SupabaseReminderRepository _reminderRepository;

  @override
  void initState() {
    super.initState();
    _reminderRepository = SupabaseReminderRepository();
  }

  void _openQuickCreateFamily() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateFamilyScreen(),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result is Family) {
          _currentFamilyId = result.id;
          _currentFamilyName = result.name;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎉 Đã liên kết gia đình mới: $_currentFamilyName (ID: $_currentFamilyId)',
          ),
          backgroundColor: const Color(0xFF005F50),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF005F50);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // TAB 0: MÀN HÌNH NHẮC NHỞ CỦA VINH (Bỏ qua Login)
          ReminderListScreen(
            familyId: _currentFamilyId,
            currentUserId: 'user_minh',
            currentUserName: 'Minh',
            familyMembers: _sampleMembers,
            repository: _reminderRepository,
          ),

          // TAB 1: MÀN HÌNH LỊCH TOÀN BỘ CỦA VINH
          CalendarPage(
            familyId: _currentFamilyId,
            currentUserId: 'user_minh',
            currentUserName: 'Minh',
            familyMembers: _sampleMembers,
            repository: _reminderRepository,
          ),

          // TAB 2: MÀN HÌNH THIẾT LẬP & TẠO GIA ĐÌNH CỦA KHOA
          const FamilySetupScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFD4ECE5),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active, color: primaryColor),
            label: 'Nhắc nhở (Vinh)',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month, color: primaryColor),
            label: 'Lịch (Vinh)',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_add_outlined),
            selectedIcon: Icon(Icons.group_add, color: primaryColor),
            label: 'Tạo Gia Đình (Khoa)',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 2
          ? FloatingActionButton.extended(
              onPressed: _openQuickCreateFamily,
              backgroundColor: const Color(0xFF07866F),
              icon: const Icon(Icons.add_home_rounded, color: Colors.white),
              label: const Text(
                'Tạo gia đình mới',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }
}
