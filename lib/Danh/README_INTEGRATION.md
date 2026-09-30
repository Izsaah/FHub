# HƯỚNG DẪN TÍCH HỢP & DEMO MODULE PAYMENT (LIB/DANH)

## 1. Cấu trúc Module (`lib/Danh`)
Module hoàn toàn self-contained, được xây dựng theo chuẩn Clean Architecture:
- `theme/danh_colors.dart`: Bảng màu chuẩn FHub `#005F50`, `#0D7A68`, `#F49D37`.
- `models/`:
  - `subscription_plan_model.dart`: Định nghĩa 3 gói (Free 4 người, Tháng 10 người, Năm 15 người).
  - `payment_transaction_model.dart`: Quản lý giao dịch, mã đơn `FHUB-XXXXXX`, trạng thái.
  - `family_subscription_model.dart`: Gói cước gắn với **Family**, không gắn với User cá nhân.
- `services/`:
  - `payment_config.dart`: Cấu hình ngân hàng/STK nhận tiền động (không hardcode).
  - `vietqr_helper.dart`: Chuẩn VietQR Napas 247 + Painter offline.
  - `payment_service.dart`: Xử lý toàn bộ logic nghiệp vụ (Pending Subscription, Polling, Webhook, Reactive Realtime).
- `widgets/`:
  - `family_premium_status_widget.dart`: Widget hiển thị hạn mức (VD: 2/4 hoặc 2/10) và trạng thái gói cho toàn bộ thành viên.
  - `premium_badge_widget.dart`: Huy hiệu VIP / Free.
  - `receiver_config_dialog.dart`: Popup đổi STK ngân hàng nhận tiền ngay trên app.
  - `countdown_timer_widget.dart`: Đếm ngược 10 phút.
  - `plan_card_widget.dart`, `payment_method_selector.dart`.
- `screens/`:
  - `premium_plan_screen.dart`: Chọn gói và so sánh quyền lợi.
  - `payment_checkout_screen.dart`: Màn hình thanh toán QR với Polling + Thanh Sandbox Simulator.
  - `payment_result_screen.dart`: Biên lai kết quả giao dịch.
  - `manage_subscription_screen.dart`: Quản lý gói cước, số lượng thành viên, hủy gia hạn, đặt lại Free (Demo).
- `danh_payment_entry.dart`: Điểm truy cập trung tâm (Entry Point).

---

## 2. Cách thức giải quyết các kịch bản nghiệp vụ của giảng viên

### Kịch bản 1: Owner mua gói Premium trước khi tạo gia đình
- `PaymentService` lưu gói ở trạng thái `_pendingSubscription`.
- Khi Owner bấm tạo gia đình (`CreateFamilyScreen`), hệ thống gọi `DanhPaymentEntry.onFamilyCreatedOrJoined(newFamilyId)`, tự động kích hoạt gói Premium cho tổ ấm mới với hạn mức 10 người.

### Kịch bản 2: Đã có gia đình rồi mới mua gói
- Gói gắn theo `family_id`. Khi thanh toán thành công, cả gia đình được nâng cấp lên 10 người.

### Kịch bản 3: Giao diện bên các thành viên khác (B)
- Widget `FamilyPremiumStatusWidget` nhúng trong `FamilyScreen` hiển thị tiến trình:
  - Nếu gói Free: `2 / 4 người`.
  - Nếu gói Premium: `2 / 10 người` kèm huy hiệu "Tổ ấm Premium".

### Kịch bản 4: Chặn khi gia đình đầy 4 người (Gói Free)
- Khi gia đình có 2/4 người, B hoặc Owner chỉ mời thêm được 2 người.
- Khi mời người thứ 3 (thành viên thứ 5), nút thêm thành viên hoặc popup mời sẽ chặn lại và hiển thị cảnh báo:
  > *"Gói Cơ Bản chỉ cho phép tối đa 4 thành viên. Vui lòng nâng cấp lên Family Hub Premium để mời thêm tối đa 10 người!"* kèm nút nâng cấp.

### Kịch bản 5: Cùng lúc A mua gói Premium thì B nhận được gì?
- Cơ chế **Reactive Realtime** (`ChangeNotifier`): Ngay khi A xác nhận thanh toán thành công, màn hình của B tự động cập nhật ngay lập tức:
  - Hạn mức tăng lên `2 / 10 người`.
  - Nút thêm thành viên lập tức mở khóa.

---

## 3. Cách test / Demo khi thuyết trình
1. Vào màn hình thanh toán VietQR.
2. Thầy xem mã QR chuẩn Napas 247 được sinh tự động. Có thể dùng app ngân hàng thật quét thử để thầy thấy tự động điền STK, tên chủ tài khoản và nội dung chuyển khoản.
3. Để demo phản ứng của hệ thống mà không mất tiền thật: Dùng thanh **Sandbox Simulator** ở dưới:
   - Bấm **"⚡ [Test] Ngân hàng báo NHẬN TIỀN THÀNH CÔNG"** $\rightarrow$ Hệ thống kích hoạt Premium ngay lập tức, chuyển sang màn hình Biên lai thành công.
   - Bấm **"Sai nội dung / Thiếu tiền"** $\rightarrow$ Hệ thống báo lỗi chuyển tiền không khớp.
   - Bấm **"Hết hạn 10 phút"** $\rightarrow$ Hệ thống hủy đơn vì quá hạn.
4. Bấm nút **"Đặt lại về Free (Demo)"** ở góc trên màn hình Quản lý gói cước để reset về ban đầu và demo lại bao nhiêu lần tùy thích.
