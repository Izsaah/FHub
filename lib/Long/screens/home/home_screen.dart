import 'package:flutter/material.dart';

import '../../services/mock_data_service.dart';
import '../../widgets/check_in_button.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/family_member_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _mockService = MockDataService();

  void _handleCheckIn() {
    setState(() {
      _mockService.checkIn(_mockService.currentUser.id);
    });
  }

  void _handleCompleteReminder(String reminderId) {
    setState(() {
      _mockService.completeReminder(reminderId);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 2. Evaluate check-in status immediately on build
    final isCheckedIn = _mockService.hasUserCheckedInToday();
    final myReminders = _mockService.getMyPendingReminders();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: 'Good morning, ${_mockService.currentUser.name}',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _mockService.currentFamily.name,
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
            ..._mockService.members.map(
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
                  // Navigate to Reminders tab (mocked)
                },
                child: const Text('View all reminders'),
              ),
          ],
        ),
      ),
    );
  }
}
