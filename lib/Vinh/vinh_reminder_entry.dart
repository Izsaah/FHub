import 'package:flutter/material.dart';
import 'models/family_member.dart';
import 'screens/reminder_list_screen.dart';
import 'services/supabase_reminder_repository.dart';

class VinhReminderApp extends StatelessWidget {
  const VinhReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Standard sample members from FAMILY HUB.docx
    final sampleMembers = [
      const FamilyMember(
        id: 'user_minh',
        name: 'Minh',
        role: 'Owner',
        familyId: 'family_1',
      ),
      const FamilyMember(
        id: 'user_mom',
        name: 'Mom',
        role: 'Member',
        familyId: 'family_1',
      ),
      const FamilyMember(
        id: 'user_dad',
        name: 'Dad',
        role: 'Member',
        familyId: 'family_1',
      ),
    ];

    final repository = SupabaseReminderRepository();

    return MaterialApp(
      title: 'Family Hub - Reminders',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Be Vietnam Pro',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D7A68),
          primary: const Color(0xFF0D7A68),
          surface: const Color(0xFFF3FBF8),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3FBF8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: ReminderListScreen(
        familyId: 'family_1',
        currentUserId: 'user_minh',
        currentUserName: 'Minh',
        familyMembers: sampleMembers,
        repository: repository,
      ),
    );
  }
}
