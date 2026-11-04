import 'package:google_generative_ai/google_generative_ai.dart';

/// Khai báo các Tools (Function Calling) chính thức cho Gemini API
class AiToolsDeclarations {
  AiToolsDeclarations._();

  /// Tool 1: Tạo công việc/nhắc nhở mới vào Firestore (AC1 & AC2)
  static final FunctionDeclaration createFamilyTaskDeclaration =
      FunctionDeclaration(
    'createFamilyTask',
    'CHỈ GỌI KHI người dùng trực tiếp ra lệnh tạo việc nhà cụ thể (VD: "Giao việc rửa bát lúc 18h", "Nhắc Bin quét nhà"). '
        'CẤM TUYỆT ĐỐI gọi tool này khi người dùng đang hỏi thắc mắc, hỏi quyền hạn, hỏi vai trò, hỏi tiến độ, hoặc tâm sự. '
        'QUY TẮC PHÂN VAI: Chỉ Bố/Mẹ/Ông/Bà mới được phân công việc nhà cho người khác. '
        'Nếu người dùng là Con cái (CHILD): CẤM giao việc nhà bắt buộc cho Bố/Mẹ hay người khác (chỉ được tạo việc cho bản thân hoặc việc chung tự nhận). '
        'Nếu con nhờ vả Bố/Mẹ (VD: đón con, mua sách vở), tiêu đề phải ghi rõ "[Lời nhờ từ con] <Nội dung>". '
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

  /// Tool 3: Thực hiện điểm danh "I'm OK" (Check-in an toàn) cho người dùng trong gia đình
  static final FunctionDeclaration performFamilyCheckInDeclaration =
      FunctionDeclaration(
    'performFamilyCheckIn',
    'Thực hiện điểm danh "I\'m OK" (Check-in an toàn) NHANH bằng giọng nói CHO PHỤ HUYNH khi họ yêu cầu: '
    '"tích i\'m ok dùm tôi", "điểm danh giúp tôi", "check in giúp tôi". '
    'CẤM GỌI TOOL NÀY cho tài khoản Con cái (CHILD), vì con cái bắt buộc phải chụp ảnh xác thực an toàn qua nút "✓ I\'M OK" trên màn hình chính.',
    Schema.object(
      properties: {
        'caption': Schema.string(
          description:
              'Lời nhắn hoặc ghi chú trạng thái check-in (ví dụ: "Đã check-in I\'m OK qua Trợ lý AI").',
        ),
      },
    ),
  );

  /// Tool 4: Xóa hoặc hủy bỏ công việc nhà khi người dùng yêu cầu
  static final FunctionDeclaration deleteFamilyTaskDeclaration =
      FunctionDeclaration(
    'deleteFamilyTask',
    'Xóa hoặc hủy bỏ một hoặc nhiều công việc nhà trong gia đình khi người dùng yêu cầu '
    '(VD: "xoá 3 công việc...", "xoá task lau nhà", "hủy việc đi chợ", "bỏ việc quét nhà"). '
    'LƯU Ý PHÂN QUYỀN: Phụ huynh có quyền xóa mọi việc nhà. Con cái CHỈ ĐƯỢC XÓA việc do chính mình tạo ra, TUYỆT ĐỐI KHÔNG xóa việc do Bố/Mẹ giao.',
    Schema.object(
      properties: {
        'keywords': Schema.array(
          description:
              'Danh sách các từ khóa hoặc tên công việc cần xóa khỏi danh sách việc nhà.',
          items: Schema.string(),
        ),
      },
      requiredProperties: ['keywords'],
    ),
  );

  /// Danh sách Tools nạp vào GenerativeModel
  static List<Tool> get allTools => [
        Tool(
          functionDeclarations: [
            createFamilyTaskDeclaration,
            saveFamilyPreferenceDeclaration,
            performFamilyCheckInDeclaration,
            deleteFamilyTaskDeclaration,
          ],
        ),
      ];
}
