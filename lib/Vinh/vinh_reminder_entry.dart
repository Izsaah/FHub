import 'package:flutter/material.dart';
import 'screens/reminder_list_screen.dart';
import 'services/firebase_reminder_repository.dart';

class VinhReminderApp extends StatelessWidget {
  const VinhReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = FirebaseReminderRepository();

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
        repository: repository,
      ),
    );
  }
}
