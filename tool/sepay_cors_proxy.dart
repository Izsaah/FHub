import 'dart:convert';
import 'dart:io';

const String _sepayEndpoint = 'https://userapi-sandbox.sepay.vn/v2/transactions';
const String _webhookTokenEndpoint =
    'https://webhook.site/token/8efa1c13-4da3-4491-84ef-cca99bba92d6/requests?sorting=newest&per_page=15';
const String _defaultToken =
    'ZMSQWHDK3RPRBDC08DX9FVJ8TG9UEJYYS2M5A4VGWH7EOLOE6BXPXL1QNWTVMNOK';
const int _port = 3099;

Future<void> main() async {
  HttpServer server;
  try {
    // Bind dual-stack (both IPv4 127.0.0.1 and IPv6 ::1 localhost on Windows)
    server = await HttpServer.bind(
      InternetAddress.anyIPv6,
      _port,
      v6Only: false,
      shared: true,
    );
  } catch (_) {
    try {
      server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _port,
        shared: true,
      );
    } catch (e) {
      stdout.writeln('SePay CORS Relay already running or port $_port busy: $e');
      return;
    }
  }

  stdout.writeln(
    'SePay CORS Relay listening on http://127.0.0.1:$_port/transactions and http://localhost:$_port/transactions',
  );

  final client = HttpClient();

  await for (final HttpRequest req in server) {
    req.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*')
      ..set('Access-Control-Allow-Private-Network', 'true')
      ..set('Cache-Control', 'no-store, no-cache, must-revalidate');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = HttpStatus.ok;
      await req.response.close();
      continue;
    }

    if (req.uri.path == '/transactions' || req.uri.path == '/') {
      try {
        final limit = req.uri.queryParameters['limit'] ?? '20';
        final targetUri = Uri.parse('$_sepayEndpoint?limit=$limit');
        final authHeader =
            req.headers.value('authorization') ?? 'Bearer $_defaultToken';

        final proxyReq = await client.getUrl(targetUri);
        proxyReq.headers.set('Authorization', authHeader);
        proxyReq.headers.set('Accept', 'application/json');

        final proxyRes =
            await proxyReq.close().timeout(const Duration(seconds: 8));
        final body = await proxyRes.transform(utf8.decoder).join();

        if (proxyRes.statusCode == 200) {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(body);
          await req.response.close();
          continue;
        }

        // Fallback to webhook.site logs if SePay userapi returns non-200
        final fallbackBody = await _fetchFromWebhookSite(client);
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentType = ContentType.json;
        req.response.write(fallbackBody);
        await req.response.close();
      } catch (e) {
        try {
          final fallbackBody = await _fetchFromWebhookSite(client);
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(fallbackBody);
          await req.response.close();
        } catch (_) {
          req.response.statusCode = HttpStatus.badGateway;
          req.response.headers.contentType = ContentType.json;
          req.response
              .write(jsonEncode({'status': 'error', 'message': e.toString()}));
          await req.response.close();
        }
      }
    } else {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    }
  }
}

Future<String> _fetchFromWebhookSite(HttpClient client) async {
  final whReq = await client.getUrl(Uri.parse(_webhookTokenEndpoint));
  whReq.headers.set('Accept', 'application/json');
  final whRes = await whReq.close().timeout(const Duration(seconds: 6));
  final whBody = await whRes.transform(utf8.decoder).join();
  final decoded = jsonDecode(whBody) as Map<String, dynamic>?;
  final rawList = decoded?['data'] as List<dynamic>? ?? [];

  final normalized = <Map<String, dynamic>>[];
  for (final item in rawList) {
    if (item is! Map<String, dynamic>) continue;
    final contentStr = item['content'] as String? ?? '';
    if (contentStr.isEmpty) continue;
    try {
      final payload = jsonDecode(contentStr) as Map<String, dynamic>;
      normalized.add({
        'id': payload['id']?.toString() ?? item['uuid']?.toString() ?? '',
        'transaction_date':
            payload['transactionDate'] ?? item['created_at'] ?? '',
        'account_number': payload['accountNumber'] ?? '0000000001',
        'transfer_type': payload['transferType'] ?? 'in',
        'amount_in': payload['transferAmount'] ?? 0,
        'transaction_content':
            payload['content'] ?? payload['description'] ?? '',
        'reference_number': payload['referenceCode'] ?? '',
        'bank_brand_name': payload['gateway'] ?? 'MBBank',
      });
    } catch (_) {}
  }

  return jsonEncode({
    'status': 'success',
    'data': normalized,
  });
}
