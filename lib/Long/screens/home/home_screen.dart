import 'package:flutter/material.dart';

import '../../services/supabase_service.dart';
import '../../models/user_model.dart';
import '../../models/family_model.dart';
import '../../models/family_member_model.dart';
import '../../models/reminder_model.dart';
import '../../widgets/check_in_button.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/family_member_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabaseService = SupabaseService();
  
  late Future<Map<String, dynamic>> _homeDataFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _homeDataFuture = _fetchHomeData();
  }

  Future<Map<String, dynamic>> _fetchHomeData() async {
    final user = await _supabaseService.getCurrentUser();
    final family = await _supabaseService.getCurrentFamily();
    final members = await _supabaseService.getFamilyMembers();
    final reminders = await _supabaseService.getMyPendingReminders();
    
    return {
      'user': user,
      'family': family,
      'members': members,
      'reminders': reminders,
    };
  }

  Future<void> _handleCheckIn() async {
    try {
      await _supabaseService.checkIn(_supabaseService.currentUserId);
      setState(() {
        _loadData();
      });
    } catch (e) {
      debugPrint('Check-in error: $e');
    }
  }

  Future<void> _handleCompleteReminder(String reminderId) async {
    try {
      await _supabaseService.completeReminder(reminderId);
      setState(() {
        _loadData();
      });
    } catch (e) {
      debugPrint('Complete reminder error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _homeDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final data = snapshot.data!;
        final UserModel user = data['user'];
        final FamilyModel? family = data['family'];
        final List<FamilyMemberModel> members = data['members'];
        final List<ReminderModel> myReminders = data['reminders'];

        // Determine check-in status
        final currentMember = members.where((m) => m.user.id == user.id).firstOrNull;
        final isCheckedIn = currentMember?.isCheckedInToday ?? false;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: CustomAppBar(
            title: 'Good morning, ${user.name}',
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: family == null 
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 60),
                    const Icon(Icons.family_restroom, size: 80, color: Colors.grey),
                    const SizedBox(height: 24),
                    const Text(
                      "You haven't joined a family yet.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Ask your family owner for an invitation code, or create a new family.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        // Navigate to family setup in the future
                        // For now we can navigate to Family tab or show a message
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please go to Family tab to join/create a family.')),
                        );
                      },
                      child: const Text('Join / Create Family'),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      family.name,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    CheckInButton(isCheckedIn: isCheckedIn, onPressed: _handleCheckIn),
                    const SizedBox(height: 32),
                    const Text(
                      'Family Today',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ...members.map(
                      (member) => FamilyMemberTile(member: member),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'My Reminders',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (myReminders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No pending reminders.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    else
                      ...myReminders.map((reminder) {
                        final timeString =
                            '${reminder.date.hour.toString().padLeft(2, '0')}:${reminder.date.minute.toString().padLeft(2, '0')}';
                        return Card(
                          elevation: 0,
                          color: Colors.blue[50],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.medication, color: Colors.blue),
                            title: Text(
                              '${reminder.title} · $timeString',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.check_circle_outline,
                                color: Colors.blue,
                              ),
                              onPressed: () => _handleCompleteReminder(reminder.id),
                            ),
                          ),
                        );
                      }),
                    if (myReminders.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          // Navigate to Reminders tab
                        },
                        child: const Text('View all reminders'),
                      ),
                  ],
                ),
          ),
        );
      },
    );
  }
}
