import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';

class MockDataService {
  // Singleton pattern for easy global access to mock state
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  MockDataService._internal();

  // --- MOCK DATA STRUCTURES ---
  // TODO (Backend/Supabase): The team member handling Supabase integration
  // should swap this entire service for a `SupabaseService`.
  // These static lists should be replaced with Supabase Streams (for real-time updates)
  // or Future calls fetching from their respective tables.

  // Mock Current User
  // TODO(Supabase): Replace with `supabase.auth.currentUser` and fetch user profile.
  final UserModel currentUser = UserModel(
    id: 'u1',
    name: 'Minh',
    email: 'minh@gmail.com',
    avatarType: 'boy',
  );

  // Mock Family
  final FamilyModel currentFamily = FamilyModel(
    id: 'f1',
    name: 'Nguyen Family',
    joinCode: 'A8K29D',
    ownerId: 'u1',
  );

  // Mock Family Members
  late List<FamilyMemberModel> members = [
    FamilyMemberModel(
      familyId: 'f1',
      user: currentUser,
      role: Role.owner,
      lastCheckInAt: null, // Not checked in yet
    ),
    FamilyMemberModel(
      familyId: 'f1',
      user: UserModel(
        id: 'u2',
        name: 'Mom',
        email: 'mom@gmail.com',
        avatarType: 'mom',
      ),
      role: Role.member,
      lastCheckInAt: DateTime.now().subtract(
        const Duration(hours: 2, minutes: 15),
      ), // Checked in earlier today
    ),
    FamilyMemberModel(
      familyId: 'f1',
      user: UserModel(
        id: 'u3',
        name: 'Dad',
        email: 'dad@gmail.com',
        avatarType: 'dad',
      ),
      role: Role.member,
      lastCheckInAt: DateTime.now().subtract(
        const Duration(hours: 3),
      ), // Checked in earlier today
    ),
  ];

  // Mock Reminders
  late List<ReminderModel> reminders = [
    ReminderModel(
      id: 'r1',
      familyId: 'f1',
      creatorId: 'u1',
      assignedTo: 'u2',
      title: 'Take medicine',
      date: DateTime.now().add(const Duration(hours: 1)),
      status: ReminderStatus.pending,
    ),
    ReminderModel(
      id: 'r2',
      familyId: 'f1',
      creatorId: 'u2',
      assignedTo: 'u1', // Assigned to Current User
      title: 'Buy milk',
      date: DateTime.now().add(const Duration(hours: 4)),
      status: ReminderStatus.pending,
    ),
    ReminderModel(
      id: 'r3',
      familyId: 'f1',
      creatorId: 'u3',
      assignedTo: 'u1', // Assigned to Current User (Completed)
      title: 'Buy vegetables',
      date: DateTime.now().subtract(const Duration(hours: 2)),
      status: ReminderStatus.completed,
      completedAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ];

  // --- Backend Simulation Methods ---

  void checkIn(String userId) {
    final memberIndex = members.indexWhere((m) => m.user.id == userId);
    if (memberIndex != -1) {
      members[memberIndex].lastCheckInAt = DateTime.now();
    }
  }

  void completeReminder(String reminderId) {
    final reminderIndex = reminders.indexWhere((r) => r.id == reminderId);
    if (reminderIndex != -1) {
      reminders[reminderIndex].status = ReminderStatus.completed;
      reminders[reminderIndex].completedAt = DateTime.now();
    }
  }

  // Helper: Auto-detect if the current user has checked in today
  bool hasUserCheckedInToday() {
    final memberIndex = members.indexWhere((m) => m.user.id == currentUser.id);
    if (memberIndex != -1) {
      return members[memberIndex].isCheckedInToday;
    }
    return false;
  }

  // Helper: Get reminders assigned to the current user (only pending ones)
  List<ReminderModel> getMyPendingReminders() {
    return reminders
        .where(
          (r) =>
              r.assignedTo == currentUser.id &&
              r.status == ReminderStatus.pending,
        )
        .toList();
  }
}
