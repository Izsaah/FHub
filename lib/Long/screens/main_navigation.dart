import 'package:flutter/material.dart';

import 'home/home_screen.dart';
import 'family/family_screen.dart';
import 'profile/profile_screen.dart';
import '../services/family_data_service.dart';
import '../utils/long_strings.dart';
import '../../Ai/screens/ai_chat_screen.dart';
import '../../Thinh/theme/app_language.dart';
import '../../Vinh/screens/reminder_list_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLanguage.isEnglish,
      builder: (context, _, child) {
        final screens = [
          HomeScreen(
            onNavigateToFamily: () => setState(() => _currentIndex = 2),
            onNavigateToReminders: () => setState(() => _currentIndex = 1),
          ),
          ReminderListScreen(
            onNavigateToFamily: () => setState(() => _currentIndex = 2),
          ),
          const FamilyScreen(),
          const ProfileScreen(),
        ];

        return Scaffold(
          body: IndexedStack(index: _currentIndex, children: screens),
          floatingActionButton: _currentIndex == 1
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'family_ai_assistant_fab',
                  backgroundColor: const Color(0xFF005F50),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  icon: const Icon(Icons.auto_awesome, size: 20),
                  label: Text(
                    LongStrings.fabAiAssistant,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AiChatScreen(
                          familyId: FamilyDataService().selectedFamilyId,
                        ),
                      ),
                    );
                  },
                ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF005F50),
            unselectedItemColor: Colors.grey,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.home),
                label: LongStrings.tabHome,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.notifications),
                label: LongStrings.tabReminders,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.family_restroom),
                label: LongStrings.tabFamily,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.person),
                label: LongStrings.tabProfile,
              ),
            ],
          ),
        );
      },
    );
  }
}
