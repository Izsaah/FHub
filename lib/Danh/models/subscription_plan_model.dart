/// Định nghĩa các gói cước của Family Hub
class SubscriptionPlanModel {
  final String id;
  final String name;
  final String description;
  final String priceFormatted;
  final int maxMembers;
  final List<String> benefits;

  const SubscriptionPlanModel({
    required this.id,
    required this.name,
    required this.description,
    required this.priceFormatted,
    required this.maxMembers,
    required this.benefits,
  });

  static const SubscriptionPlanModel freePlan = SubscriptionPlanModel(
    id: 'free',
    name: 'Gói Cơ Bản (Free)',
    description: 'Dành cho gia đình tiêu chuẩn',
    priceFormatted: 'Miễn phí',
    maxMembers: 4,
    benefits: [
      'Tối đa 4 thành viên trong tổ ấm',
      'Lời nhắc việc nhà & Check-in hằng ngày',
      'Thông báo cơ bản',
    ],
  );

  static const SubscriptionPlanModel premiumPlan = SubscriptionPlanModel(
    id: 'premium',
    name: 'Family Hub Premium',
    description: 'Mở rộng kết nối cho đại gia đình',
    priceFormatted: '49.000 đ/tháng',
    maxMembers: 10,
    benefits: [
      'Mở rộng tối đa lên 10 thành viên',
      'Áp dụng tức thì cho TOÀN BỘ gia đình',
      'Mọi thành viên đều được cấp quyền mời thêm',
      'Huy hiệu VIP hoàng gia nổi bật',
    ],
  );
}
