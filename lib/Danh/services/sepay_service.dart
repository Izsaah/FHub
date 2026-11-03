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

/// Dịch vụ kết nối và kiểm tra giao dịch với SePay (Sandbox & Production)
/// Tương thích 100% cả Flutter Web (Chrome/Edge qua Local CORS Relay + Direct), Mobile (Android/iOS) và Desktop
class SepayService {
  SepayService._();
  static final SepayService instance = SepayService._();

  static const List<String> _localWebRelayUrls = [
    'http://127.0.0.1:3099/transactions?limit=20',
    'http://localhost:3099/transactions?limit=20',
  ];

  final Set<String> _consumedTxIds = {};
  bool _relayChecked = false;
  bool _relayAvailable = false;
  bool _webCorsWarningLogged = false;

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
      if (json == null) {
        return const SepayCheckResult(status: SepayPaymentStatus.waiting);
      }

      // Hỗ trợ cả API v2 (status: 'success') và API v1 (status: 200 hoặc messages: 'success')
      final isSuccessStatus = json['status'] == 'success' ||
          json['status'] == 200 ||
          json['status'] == '200' ||
          json['messages'] == 'success';
      if (!isSuccessStatus) {
        return const SepayCheckResult(status: SepayPaymentStatus.waiting);
      }

      final rawList = json['data'] ?? json['transactions'];
      final transactions = rawList is List<dynamic> ? rawList : [];
      final cleanOrderCode = orderCode.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

      for (final tx in transactions) {
        if (tx is! Map<String, dynamic>) continue;

        final txId = tx['id']?.toString() ?? '';
        final rawContent = (tx['transaction_content'] ?? tx['content'] ?? tx['body'] ?? '').toString();
        final content = rawContent
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
    } on http.ClientException catch (_) {
      return const SepayCheckResult(status: SepayPaymentStatus.waiting);
    } catch (e) {
      if (!kIsWeb) {
        debugPrint('SepayService error: $e');
      }
      return const SepayCheckResult(status: SepayPaymentStatus.waiting);
    }
  }

  /// Lấy dữ liệu JSON giao dịch từ SePay:
  /// - Trên Flutter Web (Chrome/Edge): Ưu tiên gọi qua Local CORS Relay (127.0.0.1:3099 / localhost:3099)
  ///   không gửi custom header để tránh hoàn toàn lỗi CORS Preflight 401 của trình duyệt,
  ///   nếu không có thì fallback gọi trực tiếp.
  /// - Trên Android / iOS / Windows Desktop: Gọi trực tiếp SePay API.
  ///   Tự động thử cả Production v2 (userapi.sepay.vn/v2/transactions) và v1 (my.sepay.vn/userapi/transactions/list).
  Future<String?> _fetchTransactionsJson(String token) async {
    if (kIsWeb) {
      if (!_relayChecked) {
        _relayChecked = true;
        for (final relayUrl in _localWebRelayUrls) {
          try {
            final relayRes = await http
                .get(Uri.parse(relayUrl))
                .timeout(const Duration(milliseconds: 1500));
            if (relayRes.statusCode == 200) {
              _relayAvailable = true;
              return relayRes.body;
            }
          } catch (_) {}
        }
      } else if (_relayAvailable) {
        for (final relayUrl in _localWebRelayUrls) {
          try {
            final relayRes = await http
                .get(Uri.parse(relayUrl))
                .timeout(const Duration(milliseconds: 1500));
            if (relayRes.statusCode == 200) {
              return relayRes.body;
            }
          } catch (_) {}
        }
      }
    }

    final primaryEndpoint = PaymentConfig.sepayEndpoint;
    final candidateEndpoints = <String>[primaryEndpoint];
    if (primaryEndpoint == PaymentConfig.sepayProductionV2Endpoint) {
      candidateEndpoints.add(PaymentConfig.sepayProductionV1Endpoint);
    } else if (primaryEndpoint == PaymentConfig.sepayProductionV1Endpoint) {
      candidateEndpoints.add(PaymentConfig.sepayProductionV2Endpoint);
    }

    for (final endpoint in candidateEndpoints) {
      try {
        final uri = Uri.parse(endpoint.contains('?') ? '$endpoint&limit=20' : '$endpoint?limit=20');
        final response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          return response.body;
        }
        if (!kIsWeb) {
          debugPrint('SepayService: Endpoint $endpoint returned HTTP ${response.statusCode}: ${response.body}');
        }
      } on http.ClientException catch (_) {
        if (kIsWeb && !_webCorsWarningLogged) {
          _webCorsWarningLogged = true;
          debugPrint(
            'SepayService (Web Notice): Trình duyệt chặn CORS gọi trực tiếp SePay. Bấm nút "Mô Phỏng Nạp Thành Công" trên màn hình để kiểm tra nạp quỹ!',
          );
        }
      } catch (e) {
        if (!kIsWeb) {
          debugPrint('SepayService fetch error at $endpoint: $e');
        }
      }
    }
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
