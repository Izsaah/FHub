import 'dart:async';
import 'package:flutter/material.dart';

import 'home/home_screen.dart';
import 'family/family_screen.dart';
import 'profile/profile_screen.dart';
import '../services/family_data_service.dart';
import '../services/family_state_manager.dart';
import '../utils/long_strings.dart';
import '../widgets/app_toast.dart';
import '../../Ai/screens/ai_chat_screen.dart';
import '../../Danh/models/notification_model.dart';
import '../../Danh/services/notification_service.dart';
import '../../Thinh/theme/app_language.dart';
import '../../Vinh/screens/reminder_list_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  StreamSubscription<NotificationModel>? _notifBusSub;

  void _goToFamilyTab() {
    if (_currentIndex != 2) {
      setState(() => _currentIndex = 2);
    }
  }

  void _goToRemindersTab() {
    if (_currentIndex != 1) {
      setState(() => _currentIndex = 1);
    }
  }

  @override
  void initState() {
    super.initState();
    FamilyDataService().ensureRealtimeSync();
    FamilyStateManager().initialize();
    unawaited(NotificationService.instance.flushOutbox());
    _notifBusSub = NotificationService.instance.onNotificationDispatched.listen((notif) {
      if (!mounted) return;
      final selectedFamId = FamilyDataService().selectedFamilyIdNotifier.value;
      final currentUid = FamilyDataService().currentUserId;
      if (selectedFamId != null &&
          selectedFamId == notif.familyId &&
          (notif.targetUserId == 'ALL' || notif.targetUserId == currentUid)) {
        final msg = AppLanguage.isEnglish.value &&
                notif.titleEn != null &&
                notif.titleEn!.isNotEmpty
            ? notif.titleEn!
            : notif.title;
        AppToast.showInfo(context, msg);
      }
    });
  }

  @override
  void dispose() {
    _notifBusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            key: const ValueKey('tab_home'),
            onNavigateToFamily: _goToFamilyTab,
            onNavigateToReminders: _goToRemindersTab,
          ),
          ReminderListScreen(
            key: const ValueKey('tab_reminders'),
            isActive: _currentIndex == 1,
            onNavigateToFamily: _goToFamilyTab,
          ),
          const FamilyScreen(key: ValueKey('tab_family')),
          const ProfileScreen(key: ValueKey('tab_profile')),
        ],
      ),
      floatingActionButton: _currentIndex == 1
          ? null
          : ValueListenableBuilder<String?>(
              valueListenable: FamilyDataService().selectedFamilyIdNotifier,
              builder: (context, selectedFamId, _) {
                final hasFamily = selectedFamId != null && selectedFamId.isNotEmpty;
                if (!hasFamily) return const SizedBox.shrink();
                return FloatingActionButton.extended(
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
                          familyId: selectedFamId,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: AppLanguage.isEnglish,
        builder: (context, _, child) {
          return BottomNavigationBar(
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
          );
        },
      ),
    );
  }
}
