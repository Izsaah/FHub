import 'dart:async';
import 'dart:math';

import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';
import '../models/reminder_model.dart';
import '../models/hierarchy_role.dart';
import '../models/member_status.dart';
import '../models/check_in_feed_model.dart';
import '../models/check_in_reminder_model.dart';
import 'family_service_interface.dart';

class MockDataService implements IFamilyService {
  static final MockDataService _instance = MockDataService._internal();
  factory MockDataService() => _instance;
  MockDataService._internal() {
    _initData();
  }

  // --- CURRENT USER ---
  @override
  String get currentUserId => currentUser.id;

  final UserModel currentUser = UserModel(
    id: 'u1',
    name: 'Minh',
    email: 'minh@gmail.com',
    avatarType: 'boy',
  );

  @override
  Future<UserModel> getCurrentUser() async => currentUser;

  // --- IN-MEMORY DATA STORAGE ---
  late List<FamilyModel> _families;
  late String _currentFamilyId;
  late List<FamilyMemberModel> _allMembers;
  late List<CheckInFeedModel> _feeds;
  late List<ReminderModel> _reminders;

  // Stream controller to simulate real-time Firestore / Supabase stream
  final _membersStreamController =
      StreamController<List<FamilyMemberModel>>.broadcast();

  void _initData() {
    final now = DateTime.now();

    // 1. Multiple Families
    _families = [
      FamilyModel(
        id: 'f1',
        name: 'Gia đình Nguyễn',
        joinCode: 'A8K29D',
        ownerId: 'u1', // Current user is Owner
        createdAt: now.subtract(const Duration(days: 60)),
      ),
      FamilyModel(
        id: 'f2',
        name: 'Gia đình Ngoại',
        joinCode: 'N9B73X',
        ownerId: 'u6', // Bác Cả is Owner (Simulated Inactive > 30 days)
        createdAt: now.subtract(const Duration(days: 90)),
      ),
    ];

    _currentFamilyId = 'f1';

    // 2. Members with Hierarchy Roles and Statuses
    _allMembers = [
      // Family 1 Members
      FamilyMemberModel(
        familyId: 'f1',
        user: currentUser,
        role: Role.owner,
        hierarchyRole: HierarchyRole.parent,
        status: MemberStatus.active,
        lastActiveAt: now,
        lastCheckInAt: null, // User not checked in yet today
      ),
      FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(
          id: 'u2',
          name: 'Mẹ Lan',
          email: 'lan@gmail.com',
          avatarType: 'mom',
        ),
        role: Role.member,
        hierarchyRole: HierarchyRole.grandparent,
        status: MemberStatus.active,
        lastActiveAt: now.subtract(const Duration(hours: 2)),
        lastCheckInAt: now.subtract(const Duration(hours: 2, minutes: 15)),
      ),
      FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(
          id: 'u3',
          name: 'Bố Hùng',
          email: 'hung@gmail.com',
          avatarType: 'dad',
        ),
        role: Role.member,
        hierarchyRole: HierarchyRole.grandparent,
        status: MemberStatus.active,
        lastActiveAt: now.subtract(const Duration(hours: 5)),
        lastCheckInAt: null, // Grandparent has not checked in today!
      ),
      FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(
          id: 'u4',
          name: 'Cụ Cố (Tưởng niệm)',
          email: 'cu@gmail.com',
          avatarType: 'grandpa',
        ),
        role: Role.member,
        hierarchyRole: HierarchyRole.grandparent,
        status: MemberStatus.memorialized, // Memorialized member
        lastActiveAt: now.subtract(const Duration(days: 400)),
        lastCheckInAt: null,
      ),
      FamilyMemberModel(
        familyId: 'f1',
        user: UserModel(
          id: 'u5',
          name: 'Chú Tuấn (Đi công tác)',
          email: 'tuan@gmail.com',
          avatarType: 'uncle',
        ),
        role: Role.member,
        hierarchyRole: HierarchyRole.parent,
        status: MemberStatus.deactivated, // Deactivated member
        lastActiveAt: now.subtract(const Duration(days: 15)),
        lastCheckInAt: null,
      ),

      // Family 2 Members
      FamilyMemberModel(
        familyId: 'f2',
        user: UserModel(
          id: 'u6',
          name: 'Bác Cả',
          email: 'bacca@gmail.com',
          avatarType: 'dad',
        ),
        role: Role.owner,
        hierarchyRole: HierarchyRole.parent,
        status: MemberStatus.active,
        // Inactive for 35 days -> Eligible for PARENT takeover!
        lastActiveAt: now.subtract(const Duration(days: 35)),
        lastCheckInAt: null,
      ),
      FamilyMemberModel(
        familyId: 'f2',
        user: currentUser, // Minh is also in Family 2 as PARENT!
        role: Role.member,
        hierarchyRole: HierarchyRole.parent,
        status: MemberStatus.active,
        lastActiveAt: now,
        lastCheckInAt: null,
      ),
      FamilyMemberModel(
        familyId: 'f2',
        user: UserModel(
          id: 'u7',
          name: 'Bà Ngoại',
          email: 'bangoai@gmail.com',
          avatarType: 'grandma',
        ),
        role: Role.member,
        hierarchyRole: HierarchyRole.grandparent,
        status: MemberStatus.active,
        lastActiveAt: now.subtract(const Duration(hours: 10)),
        lastCheckInAt: null,
      ),
    ];

    // 3. Initial Mock Photo Feeds
    _feeds = [
      CheckInFeedModel(
        id: 'feed_1',
        familyId: 'f1',
        userId: 'u2',
        userName: 'Mẹ Lan',
        userAvatarType: 'mom',
        imageUrl: 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=500',
        caption: 'Bữa sáng lành mạnh với rau củ và sữa tươi, cả nhà ăn sáng chưa?',
        createdAt: now.subtract(const Duration(hours: 2, minutes: 15)),
      ),
    ];

    // 4. Existing Reminders
    _reminders = [
      ReminderModel(
        id: 'r1',
        familyId: 'f1',
        creatorId: 'u1',
        assignedTo: 'u2',
        title: 'Uống thuốc huyết áp buổi sáng',
        date: now.add(const Duration(hours: 1)),
        status: ReminderStatus.pending,
      ),
      ReminderModel(
        id: 'r2',
        familyId: 'f1',
        creatorId: 'u2',
        assignedTo: 'u1',
        title: 'Mua sữa cho ông bà',
        date: now.add(const Duration(hours: 4)),
        status: ReminderStatus.pending,
      ),
    ];
  }

  // --- MULTI-FAMILY & SWITCHER ---

  @override
  Future<List<FamilyModel>> getMyFamilies() async {
    final myFamilyIds = _allMembers
        .where((m) => m.user.id == currentUserId)
        .map((m) => m.familyId)
        .toSet();

    return _families.where((f) => myFamilyIds.contains(f.id)).toList();
  }

  @override
  Future<FamilyModel?> getCurrentFamily() async {
    final myFams = await getMyFamilies();
    if (myFams.isEmpty) return null;
    return myFams.firstWhere(
      (f) => f.id == _currentFamilyId,
      orElse: () => myFams.first,
    );
  }

  FamilyModel get currentFamily {
    return _families.firstWhere(
      (f) => f.id == _currentFamilyId,
      orElse: () => _families.first,
    );
  }

  @override
  Future<void> switchFamily(String familyId) async {
    final exists = _families.any((f) => f.id == familyId);
    if (!exists) throw Exception('Gia đình không tồn tại.');
    _currentFamilyId = familyId;
    _broadcastMembers();
  }

  // --- CREATION & JOINING ---

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  @override
  Future<FamilyModel> createFamily({
    required String name,
    HierarchyRole hierarchyRole = HierarchyRole.parent,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw Exception('Tên gia đình không được để trống.');

    final newFamilyId = 'f_${DateTime.now().millisecondsSinceEpoch}';
    final joinCode = _generateJoinCode();

    final newFamily = FamilyModel(
      id: newFamilyId,
      name: trimmedName,
      joinCode: joinCode,
      ownerId: currentUserId,
      createdAt: DateTime.now(),
    );

    _families.add(newFamily);

    final newMember = FamilyMemberModel(
      familyId: newFamilyId,
      user: currentUser,
      role: Role.owner,
      hierarchyRole: hierarchyRole,
      status: MemberStatus.active,
      lastActiveAt: DateTime.now(),
      lastCheckInAt: null,
    );

    _allMembers.add(newMember);
    _currentFamilyId = newFamilyId;
    _broadcastMembers();

    return newFamily;
  }

  @override
  Future<FamilyModel> joinFamily({
    required String joinCode,
    HierarchyRole hierarchyRole = HierarchyRole.child,
  }) async {
    final trimmedCode = joinCode.trim().toUpperCase();
    if (trimmedCode.length != 6) {
      throw Exception('Mã tham gia phải gồm đúng 6 ký tự.');
    }

    final targetFamily = _families.firstWhere(
      (f) => f.joinCode.toUpperCase() == trimmedCode,
      orElse: () => throw Exception('Không tìm thấy gia đình với mã $trimmedCode.'),
    );

    final alreadyMember = _allMembers.any(
      (m) => m.familyId == targetFamily.id && m.user.id == currentUserId,
    );

    if (alreadyMember) {
      throw Exception('Bạn đã là thành viên của ${targetFamily.name} rồi.');
    }

    final newMember = FamilyMemberModel(
      familyId: targetFamily.id,
      user: currentUser,
      role: Role.member,
      hierarchyRole: hierarchyRole,
      status: MemberStatus.active,
      lastActiveAt: DateTime.now(),
      lastCheckInAt: null,
    );

    _allMembers.add(newMember);
    _currentFamilyId = targetFamily.id;
    _broadcastMembers();

    return targetFamily;
  }

  // --- MEMBERS ---

  List<FamilyMemberModel> get members =>
      _allMembers.where((m) => m.familyId == _currentFamilyId).toList();

  @override
  Future<List<FamilyMemberModel>> getFamilyMembers({String? familyId}) async {
    final targetId = familyId ?? _currentFamilyId;
    return _allMembers.where((m) => m.familyId == targetId).toList();
  }

  @override
  Stream<List<FamilyMemberModel>> streamFamilyMembers({String? familyId}) {
    final targetId = familyId ?? _currentFamilyId;
    return _membersStreamController.stream.map(
      (list) => list.where((m) => m.familyId == targetId).toList(),
    );
  }

  void _broadcastMembers() {
    _membersStreamController.add(List.unmodifiable(_allMembers));
  }

  // --- STATUS & OWNERSHIP MANAGEMENT ---

  @override
  Future<void> updateOwnerLastActive() async {
    final now = DateTime.now();
    for (var member in _allMembers) {
      if (member.user.id == currentUserId && member.isOwner) {
        member.lastActiveAt = now;
      }
    }
  }

  @override
  Future<void> updateMemberStatus(
    String targetUserId,
    MemberStatus newStatus, {
    String? familyId,
  }) async {
    final targetFamId = familyId ?? _currentFamilyId;
    final currentMember = _allMembers.firstWhere(
      (m) => m.familyId == targetFamId && m.user.id == currentUserId,
      orElse: () => throw Exception('Không tìm thấy tư cách thành viên.'),
    );

    if (!currentMember.isOwner) {
      throw Exception('Chỉ Chủ phòng (Owner) mới có quyền đổi trạng thái thành viên.');
    }

    if (targetUserId == currentUserId) {
      throw Exception('Owner không thể tự đổi trạng thái của chính mình.');
    }

    final targetMember = _allMembers.firstWhere(
      (m) => m.familyId == targetFamId && m.user.id == targetUserId,
      orElse: () => throw Exception('Thành viên không tồn tại trong gia đình.'),
    );

    targetMember.status = newStatus;
    _broadcastMembers();
  }

  @override
  Future<void> transferOwnership(
    String newOwnerUserId, {
    String? familyId,
  }) async {
    final targetFamId = familyId ?? _currentFamilyId;
    final currentMember = _allMembers.firstWhere(
      (m) => m.familyId == targetFamId && m.user.id == currentUserId,
      orElse: () => throw Exception('Bạn không thuộc gia đình này.'),
    );

    if (!currentMember.isOwner) {
      throw Exception('Chỉ Owner hiện tại mới có quyền chuyển nhượng Chủ phòng.');
    }

    final targetMember = _allMembers.firstWhere(
      (m) => m.familyId == targetFamId && m.user.id == newOwnerUserId,
      orElse: () => throw Exception('Thành viên nhận chuyển nhượng không tồn tại.'),
    );

    if (targetMember.hierarchyRole != HierarchyRole.parent) {
      throw Exception('Quyền Owner chỉ có thể chuyển giao cho thành viên vai vế Bố Mẹ (PARENT).');
    }

    if (targetMember.status != MemberStatus.active) {
      throw Exception('Thành viên phải ở trạng thái Hoạt động để nhận quyền Owner.');
    }

    // Perform ownership swap
    final famIndex = _families.indexWhere((f) => f.id == targetFamId);
    if (famIndex != -1) {
      _families[famIndex] = _families[famIndex].copyWith(ownerId: newOwnerUserId);
    }

    currentMember.role = Role.member;
    targetMember.role = Role.owner;
    targetMember.lastActiveAt = DateTime.now();

    _broadcastMembers();
  }

  @override
  bool isTakeoverEligible({String? familyId}) {
    final targetFamId = familyId ?? _currentFamilyId;
    final currentMember = _allMembers.firstWhere(
      (m) => m.familyId == targetFamId && m.user.id == currentUserId,
      orElse: () => FamilyMemberModel(
        familyId: targetFamId,
        user: currentUser,
        role: Role.member,
      ),
    );

    // Current user must be a PARENT and ACTIVE and NOT already owner
    if (currentMember.hierarchyRole != HierarchyRole.parent ||
        currentMember.status != MemberStatus.active ||
        currentMember.isOwner) {
      return false;
    }

    // Find the current owner
    final ownerMember = _allMembers.firstWhere(
      (m) => m.familyId == targetFamId && m.isOwner,
      orElse: () => FamilyMemberModel(
        familyId: targetFamId,
        user: UserModel(id: 'dummy', name: '', email: ''),
        role: Role.owner,
      ),
    );

    if (ownerMember.user.id == 'dummy') return false;

    // Check if Owner is deactivated for > 30 days or has not opened app > 30 days
    final now = DateTime.now();
    final isOwnerDeactivated = ownerMember.status == MemberStatus.deactivated;
    final lastActive = ownerMember.lastActiveAt;
    final isInactiveOver30Days = lastActive != null && now.difference(lastActive).inDays >= 30;

    return isOwnerDeactivated || isInactiveOver30Days;
  }

  @override
  Future<void> claimOwnership({String? familyId}) async {
    final targetFamId = familyId ?? _currentFamilyId;
    if (!isTakeoverEligible(familyId: targetFamId)) {
      throw Exception('Gia đình chưa đủ điều kiện để tiếp quản quyền Owner (Owner phải vắng mặt hoặc tạm ngưng > 30 ngày).');
    }

    final currentMember = _allMembers.firstWhere(
      (m) => m.familyId == targetFamId && m.user.id == currentUserId,
    );

    final ownerMember = _allMembers.firstWhere(
      (m) => m.familyId == targetFamId && m.isOwner,
    );

    final famIndex = _families.indexWhere((f) => f.id == targetFamId);
    if (famIndex != -1) {
      _families[famIndex] = _families[famIndex].copyWith(ownerId: currentUserId);
    }

    ownerMember.role = Role.member;
    currentMember.role = Role.owner;
    currentMember.lastActiveAt = DateTime.now();

    _broadcastMembers();
  }

  // --- CHECK-IN & FEEDS ---

  @override
  Future<void> checkIn(
    String userId, {
    String? imageUrl,
    String? caption,
    String? familyId,
  }) async {
    final targetFamId = familyId ?? _currentFamilyId;

    // Rule: User can ONLY check in for themselves
    if (userId != currentUserId) {
      throw Exception('Mỗi người chỉ được check-in cho chính mình, không được check-in hộ.');
    }

    final memberIndex = _allMembers.indexWhere(
      (m) => m.familyId == targetFamId && m.user.id == userId,
    );

    if (memberIndex == -1) {
      throw Exception('Không tìm thấy thành viên trong gia đình.');
    }

    final member = _allMembers[memberIndex];

    // Rule: AC1 - Check-in 1 time per day
    if (member.isCheckedInToday) {
      throw Exception("You're already checked in.");
    }

    final now = DateTime.now();
    member.lastCheckInAt = now;
    member.lastCheckInDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // If attached photo or caption, push to feed
    if (imageUrl != null || caption != null) {
      final newFeed = CheckInFeedModel(
        id: 'feed_${now.millisecondsSinceEpoch}',
        familyId: targetFamId,
        userId: currentUserId,
        userName: currentUser.name,
        userAvatarType: currentUser.avatarType,
        imageUrl: imageUrl,
        caption: caption,
        createdAt: now,
      );
      _feeds.insert(0, newFeed);
    }

    // Cancel reminders for today
    cancelRemindersForUser(userId, familyId: targetFamId);

    _broadcastMembers();
  }

  @override
  Future<List<CheckInFeedModel>> getCheckInFeeds({String? familyId}) async {
    final targetFamId = familyId ?? _currentFamilyId;
    return _feeds.where((f) => f.familyId == targetFamId).toList();
  }

  // --- SIMULATED REMINDERS (08:00, 14:00, 20:00) ---

  @override
  List<CheckInReminderItem> getSimulatedReminders({String? familyId}) {
    final targetFamId = familyId ?? _currentFamilyId;
    final famMembers = _allMembers.where((m) => m.familyId == targetFamId).toList();

    // Look for Grandparents
    final grandparents = famMembers.where(
      (m) => m.hierarchyRole == HierarchyRole.grandparent && m.status == MemberStatus.active,
    );

    final parents = famMembers.where(
      (m) => m.hierarchyRole == HierarchyRole.parent && m.status == MemberStatus.active,
    );

    final List<CheckInReminderItem> results = [];
    final now = DateTime.now();

    for (var gp in grandparents) {
      final isCheckedIn = gp.isCheckedInToday;

      // Slot 1: 08:00 AM (Gentle reminder on Grandparent device)
      results.add(CheckInReminderItem(
        id: 'rem_${gp.user.id}_8am',
        familyId: targetFamId,
        targetMemberId: gp.user.id,
        targetMemberName: gp.user.name,
        recipientMemberId: gp.user.id,
        recipientMemberName: gp.user.name,
        slot: ReminderTimeSlot.slot8AM,
        message: 'Chào buổi sáng ${gp.user.name}! Hãy bấm "I\'M OK" để con cháu yên tâm nhé.',
        isVibration: false,
        isCancelled: isCheckedIn,
        scheduledTime: DateTime(now.year, now.month, now.day, 8, 0),
      ));

      // Slot 2: 14:00 PM (+6h: Vibration on Grandparent device)
      results.add(CheckInReminderItem(
        id: 'rem_${gp.user.id}_2pm',
        familyId: targetFamId,
        targetMemberId: gp.user.id,
        targetMemberName: gp.user.name,
        recipientMemberId: gp.user.id,
        recipientMemberName: gp.user.name,
        slot: ReminderTimeSlot.slot2PM,
        message: 'Đã 14:00 rồi! ${gp.user.name} chưa check-in hôm nay, gia đình đang lo lắng đó ạ.',
        isVibration: true,
        isCancelled: isCheckedIn,
        scheduledTime: DateTime(now.year, now.month, now.day, 14, 0),
      ));

      // Slot 3: 20:00 PM (+12h: Vibration alert on Parent devices)
      for (var p in parents) {
        results.add(CheckInReminderItem(
          id: 'rem_${gp.user.id}_8pm_${p.user.id}',
          familyId: targetFamId,
          targetMemberId: gp.user.id,
          targetMemberName: gp.user.name,
          recipientMemberId: p.user.id,
          recipientMemberName: p.user.name,
          slot: ReminderTimeSlot.slot8PM,
          message: 'Cảnh báo: Đã quá 12 tiếng từ giờ hẹn nhưng ${gp.user.name} chưa check-in hôm nay, gia đình hãy gọi điện kiểm tra nhé!',
          isVibration: true,
          isCancelled: isCheckedIn,
          scheduledTime: DateTime(now.year, now.month, now.day, 20, 0),
        ));
      }
    }

    return results;
  }

  @override
  void cancelRemindersForUser(String userId, {String? familyId}) {
    // In-memory simulation: when user checks in, their status updates to isCheckedInToday = true,
    // which automatically marks subsequent reminder slots as cancelled!
    _broadcastMembers();
  }

  // --- EXISTING COMPATIBILITY METHODS ---

  List<ReminderModel> get reminders => _reminders;

  void completeReminder(String reminderId) {
    final reminderIndex = _reminders.indexWhere((r) => r.id == reminderId);
    if (reminderIndex != -1) {
      _reminders[reminderIndex].status = ReminderStatus.completed;
      _reminders[reminderIndex].completedAt = DateTime.now();
    }
  }

  bool hasUserCheckedInToday() {
    final currentMember = _allMembers.firstWhere(
      (m) => m.familyId == _currentFamilyId && m.user.id == currentUser.id,
      orElse: () => FamilyMemberModel(
        familyId: _currentFamilyId,
        user: currentUser,
        role: Role.member,
      ),
    );
    return currentMember.isCheckedInToday;
  }

  List<ReminderModel> getMyPendingReminders() {
    return _reminders
        .where(
          (r) =>
              r.assignedTo == currentUser.id &&
              r.status == ReminderStatus.pending,
        )
        .toList();
  }
}
