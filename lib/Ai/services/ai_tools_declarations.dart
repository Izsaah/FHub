import 'package:google_generative_ai/google_generative_ai.dart';

/// Khai báo các Tools (Function Calling) chính thức cho Gemini API
class AiToolsDeclarations {
  AiToolsDeclarations._();

  /// Tool 1: Tạo công việc/nhắc nhở mới vào Firestore (AC1 & AC2)
  static final FunctionDeclaration createFamilyTaskDeclaration =
      FunctionDeclaration(
    'createFamilyTask',
    'Tạo một công việc hoặc lời nhắc mới cho gia đình. '
        'Nếu là việc mở cho các con nhận (Open Task), đặt assignedTo="ALL" và isOpenTask=true.',
    Schema.object(
      properties: {
        'title': Schema.string(
          description:
              'Tiêu đề công việc cụ thể. Ví dụ: "Phụ mẹ làm việc nhà", "Mua sữa (Vinamilk)", "Tưới cây ban công".',
        ),
        'assignedTo': Schema.string(
          description:
              'ID thành viên được giao việc, hoặc "ALL" nếu là việc mở cho các con trong nhà tự nhận.',
        ),
        'assignedToName': Schema.string(
          description:
              'Tên hiển thị của người nhận việc (ví dụ: "Bố", "Minh", "Bé Na", hoặc "Việc chung").',
        ),
        'date': Schema.string(
          description: 'Ngày cần làm định dạng dd/MM/yyyy (ví dụ: 21/10/2026).',
        ),
        'time': Schema.string(
          description: 'Giờ cần làm định dạng HH:mm (ví dụ: 08:30 hoặc 17:00).',
        ),
        'isOpenTask': Schema.boolean(
          description:
              'true nếu là việc mở không gán cho ai để các con tự nhận; false nếu giao đích danh.',
        ),
      },
      requiredProperties: ['title', 'date', 'time'],
    ),
  );

  /// Tool 2: Lưu thói quen / sở thích cá nhân hóa của gia đình vào bộ nhớ Firestore (AC2)
  static final FunctionDeclaration saveFamilyPreferenceDeclaration =
      FunctionDeclaration(
    'saveFamilyPreference',
    'Lưu hoặc cập nhật thói quen, sở thích, thương hiệu ưa dùng của gia đình vào bộ nhớ dài hạn.',
    Schema.object(
      properties: {
        'keyword': Schema.string(
          description:
              'Từ khóa của thói quen/đồ vật. Ví dụ: "sữa", "nước giặt", "gạo", "cà phê".',
        ),
        'value': Schema.string(
          description:
              'Chi tiết thói quen đã được người dùng xác nhận. Ví dụ: "Vinamilk", "Omo matic", "ST25", "đen đá không đường".',
        ),
        'category': Schema.string(
          description: 'Danh mục (ví dụ: "shopping", "habit", "chore").',
        ),
      },
      requiredProperties: ['keyword', 'value'],
    ),
  );

  /// Danh sách Tools nạp vào GenerativeModel
  static List<Tool> get allTools => [
        Tool(
          functionDeclarations: [
            createFamilyTaskDeclaration,
            saveFamilyPreferenceDeclaration,
          ],
        ),
      ];
}
