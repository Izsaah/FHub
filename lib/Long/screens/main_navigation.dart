import 'package:flutter/material.dart';

import 'home/home_screen.dart';
import 'family/family_screen.dart';
import 'profile/profile_screen.dart';
import '../services/family_data_service.dart';
import '../services/family_state_manager.dart';
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
  void initState() {
    super.initState();
    FamilyDataService().ensureRealtimeSync();
    FamilyStateManager().initialize();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = FamilyDataService();
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppLanguage.isEnglish,
        dataService.selectedFamilyIdNotifier,
        dataService.membershipRevisionNotifier,
      ]),
      builder: (context, _) {
        final hasFamily = dataService.hasActiveSelectedFamily;
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
          floatingActionButton: (_currentIndex == 1 || !hasFamily)
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
                    final selectedFamId = dataService.selectedFamilyId;
                    if (selectedFamId == null || selectedFamId.isEmpty) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AiChatScreen(
                          familyId: selectedFamId,
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
