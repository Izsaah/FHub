import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'payment_config.dart';

enum SepayPaymentStatus {
  waiting,
  success,
  underpaid,
}

class SepayCheckResult {
  final SepayPaymentStatus status;
  final int amountIn;
  final int expectedAmount;
  final Map<String, dynamic>? transaction;

  const SepayCheckResult({
    required this.status,
    this.amountIn = 0,
    this.expectedAmount = PaymentConfig.defaultAmount,
    this.transaction,
  });

  bool get isSuccess => status == SepayPaymentStatus.success;
  bool get isUnderpaid => status == SepayPaymentStatus.underpaid;
}

/// Dịch vụ kết nối và kiểm tra giao dịch với SePay Sandbox
/// Tương thích 100% cả Flutter Web (Chrome/Edge qua Local CORS Relay + Direct), Mobile (Android/iOS) và Desktop
class SepayService {
  SepayService._();
  static final SepayService instance = SepayService._();

  static const List<String> _localWebRelayUrls = [
    'http://127.0.0.1:3099/transactions?limit=20',
    'http://localhost:3099/transactions?limit=20',
  ];

  final Set<String> _consumedTxIds = {};

  /// Kiểm tra trạng thái giao dịch theo mã đơn hàng [orderCode]
  /// BẮT BUỘC KHỚP CHÍNH XÁC MÃ ĐƠN HÀNG (FHUBxxxxxx)
  Future<SepayCheckResult> checkPayment({
    required String orderCode,
    int expectedAmount = PaymentConfig.defaultAmount,
  }) async {
    final token = PaymentConfig.apiKey.trim();
    if (token.isEmpty) {
      debugPrint('SepayService: API Key is empty.');
      return const SepayCheckResult(status: SepayPaymentStatus.waiting);
    }

    try {
      final responseBody = await _fetchTransactionsJson(token);
      if (responseBody == null) {
        return const SepayCheckResult(status: SepayPaymentStatus.waiting);
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>?;
      if (json == null || json['status'] != 'success') {
        return const SepayCheckResult(status: SepayPaymentStatus.waiting);
      }

      final transactions = json['data'] as List<dynamic>? ?? [];
      final cleanOrderCode = orderCode.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

      for (final tx in transactions) {
        if (tx is! Map<String, dynamic>) continue;

        final txId = tx['id']?.toString() ?? '';
        final content = (tx['transaction_content'] as String? ?? '')
            .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
            .toUpperCase();
        final amountIn = _parseAmount(tx['amount_in']);

        // BẮT BUỘC: Khớp chính xác mã đơn hàng (FHUBxxxxxx)
        final bool isOrderMatch = cleanOrderCode.isNotEmpty && content.contains(cleanOrderCode);

        if (isOrderMatch && !_consumedTxIds.contains(txId)) {
          if (amountIn >= expectedAmount) {
            if (txId.isNotEmpty) _consumedTxIds.add(txId);
            debugPrint(
              'SepayService: MATCH SUCCESS! TxId: $txId Content: $content Amount: $amountIn',
            );
            return SepayCheckResult(
              status: SepayPaymentStatus.success,
              amountIn: amountIn,
              expectedAmount: expectedAmount,
              transaction: tx,
            );
          } else if (amountIn > 0) {
            debugPrint(
              'SepayService: UNDERPAID! Received $amountIn, expected $expectedAmount',
            );
            return SepayCheckResult(
              status: SepayPaymentStatus.underpaid,
              amountIn: amountIn,
              expectedAmount: expectedAmount,
              transaction: tx,
            );
          }
        }
      }

      return const SepayCheckResult(status: SepayPaymentStatus.waiting);
    } catch (e) {
      debugPrint('SepayService error: $e');
      return const SepayCheckResult(status: SepayPaymentStatus.waiting);
    }
  }

  /// Lấy dữ liệu JSON giao dịch từ SePay:
  /// - Trên Flutter Web (Chrome/Edge): Ưu tiên gọi qua Local CORS Relay (127.0.0.1:3099 / localhost:3099)
  ///   không gửi custom header để tránh hoàn toàn lỗi CORS Preflight 401 của trình duyệt,
  ///   nếu không có thì fallback gọi trực tiếp.
  /// - Trên Android / iOS / Windows Desktop: Gọi trực tiếp SePay Sandbox API.
  Future<String?> _fetchTransactionsJson(String token) async {
    if (kIsWeb) {
      for (final relayUrl in _localWebRelayUrls) {
        try {
          final relayRes = await http
              .get(Uri.parse(relayUrl))
              .timeout(const Duration(seconds: 4));
          if (relayRes.statusCode == 200) {
            return relayRes.body;
          }
        } catch (_) {
          // Thử tiếp URL relay kế tiếp hoặc fallback
        }
      }
    }

    final uri = Uri.parse('${PaymentConfig.sepaySandboxEndpoint}?limit=20');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      return response.body;
    }
    debugPrint('SepayService: HTTP ${response.statusCode}: ${response.body}');
    return null;
  }

  int _parseAmount(dynamic val) {
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) {
      return double.tryParse(val.replaceAll(',', ''))?.toInt() ?? 0;
    }
    return 0;
  }
}
