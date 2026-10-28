import '../../Thinh/theme/app_language.dart';

/// Quản lý chuỗi đa ngôn ngữ (Tiếng Việt & Tiếng Anh) riêng cho thư mục Long (Home, Family, Profile)
/// và đồng bộ hóa với hệ thống AppLanguage toàn ứng dụng.
class LongStrings {
  LongStrings._();

  static bool get isEnglish => AppLanguage.isEnglish.value;

  static String t(String vi, String en) => AppLanguage.text(vi, en);

  // ---------------------------------------------------------------------------
  // Home Screen
  // ---------------------------------------------------------------------------
  static String goodMorning(String name) =>
      t('Chào buổi sáng, $name', 'Good morning, $name');
  static String get familyToday => t('Gia đình hôm nay', 'Family Today');
  static String membersCount(int count) =>
      t('$count thành viên', '$count members');
  static String get myReminders => t('Việc cần làm của tôi', 'My Reminders');
  static String get noPendingReminders =>
      t('Không có lời nhắc nào đang chờ.', 'No pending reminders.');
  static String get viewAllReminders =>
      t('Xem tất cả lời nhắc', 'View all reminders');
  static String get selectFamily => t('Chọn gia đình:', 'Select family:');
  static String get selectFamilyTitle =>
      t('Chọn gia đình hiển thị', 'Select Active Family');
  static String get selectFamilyDesc => t(
        'Chuyển đổi gia đình đang xem trên bảng tin và thông tin gia đình.',
        'Switch active family for dashboard and family details.',
      );
  static String houses(int count) => t('$count nhà', '$count families');
  static String get addOrJoinFamily =>
      t('+ Tạo hoặc tham gia gia đình khác', '+ Create or join another family');
  static String get checkIn => t('Điểm danh hôm nay', 'Check In Today');
  static String get checkedIn => t('Đã điểm danh', 'Checked In');
  static String get checkInSuccess =>
      t('Điểm danh thành công!', 'Checked in successfully!');
  static String get notJoinedFamilyYet =>
      t('Bạn chưa tham gia gia đình nào.', "You haven't joined a family yet.");
  static String get askFamilyOwner => t(
        'Hãy yêu cầu chủ gia đình cấp mã mời, hoặc tạo gia đình mới để cùng chia sẻ bảng tin và phân chia việc nhà.',
        'Ask your family owner for an invitation code, or create a new family to share dashboard and manage tasks together.',
      );
  static String get joinOrCreateFamily =>
      t('Tạo hoặc tham gia gia đình', 'Create or Join Family');
  static String get goToFamilyTab =>
      t('Đến mục Gia đình', 'Go to Family');
  static String get familyShortcutTooltip =>
      t('Xem trang gia đình', 'View family screen');
  static String get completeTaskSuccess =>
      t('Đã hoàn thành lời nhắc!', 'Task completed!');

  // ---------------------------------------------------------------------------
  // Family Screen
  // ---------------------------------------------------------------------------
  static String get lovingHome => t('Tổ Ấm Yêu Thương', 'Family Hub');
  static String get welcomeFamilyHub =>
      t('Chào mừng đến với Family Hub', 'Welcome to Family Hub');
  static String get notInFamilyDesc => t(
        'Bạn chưa tham gia gia đình nào. Hãy tạo một gia đình hoặc tham gia bằng mã mời để bắt đầu.',
        "You aren't in a family yet. Create one or join an existing family to get started.",
      );
  static String get setUpYourFamily =>
      t('Thiết lập gia đình của bạn', 'Set Up Your Family');
  static String get familyCode => t('Mã gia đình', 'Family Code');
  static String get copyCodeSuccess =>
      t('Đã sao chép mã mời!', 'Invitation code copied!');
  static String get copyCodeFailed =>
      t('Không thể sao chép mã', 'Failed to copy code');
  static String get dailyCheckIn =>
      t('Điểm danh hôm nay', 'Daily Check-in');
  static String get manageMembers =>
      t('Danh sách thành viên', 'Family Members');
  static String get leaveFamily => t('Rời gia đình', 'Leave family');
  static String get deleteFamily => t('Xóa gia đình', 'Delete family');
  static String get singleFamilyBadge =>
      t('Đang tham gia 1 gia đình', '1 family joined');
  static String get addNewMember =>
      t('Thêm thành viên mới', 'Add new member');
  static String familyMembersHeader(int count) =>
      t('Thành viên trong tổ ấm ($count)', 'Family members ($count)');
  static String get codePrefix => t('Mã: ', 'Code: ');

  // ---------------------------------------------------------------------------
  // Profile Screen
  // ---------------------------------------------------------------------------
  static String get profileTitle => t('Tổ Ấm Yêu Thương', 'Family Hub');
  static String get profileSubtitle => t('Thông tin cá nhân', 'Profile details');
  static String get memberBadge => t('Thành viên', 'Member');
  static String get currentFamilyTitle => t('Gia đình hiện tại', 'Current family');
  static String get notJoinedJoinNow =>
      t('Chưa tham gia • Tham gia ngay', 'Not joined • Join now');
  static String get currentFamilySingle =>
      t('Gia đình hiện tại (1)', 'Current family (1)');
  static String get addOrJoin => t('Thêm / Tham gia', 'Add / Join');
  static String joinedFamiliesCount(int count) =>
      t('Gia đình tham gia ($count gia đình)', 'Joined families ($count)');
  static String get manageOrAdd => t('Quản lý / Thêm', 'Manage / Add');
  static String get activeTag => t('Đang chọn', 'Active');
  static String get appLanguageTitle =>
      t('Ngôn ngữ hiển thị', 'App Language');
  static String get logoutButton =>
      t('Đăng xuất khỏi thiết bị này', 'Log out from this device');
  static String get logoutConfirmTitle => t('Đăng xuất?', 'Log out?');
  static String get logoutConfirmDesc => t(
        'Bạn có chắc muốn đăng xuất khỏi thiết bị này không?',
        'Are you sure you want to log out of this device?',
      );
  static String get cancel => t('Hủy', 'Cancel');
  static String get logout => t('Đăng xuất', 'Log out');

  // ---------------------------------------------------------------------------
  // Main Navigation
  // ---------------------------------------------------------------------------
  static String get tabHome => t('Trang chủ', 'Home');
  static String get tabReminders => t('Lời nhắc', 'Reminders');
  static String get tabFamily => t('Gia đình', 'Family');
  static String get tabProfile => t('Cá nhân', 'Profile');
  static String get fabAiAssistant => t('Trợ lý AI', 'AI Assistant');
}
