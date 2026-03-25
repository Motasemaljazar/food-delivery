import 'dart:convert';
import 'package:http/http.dart' as http;

/// API client used by admin_app screens (customer-style flows: menu, orders, complaints, notifications).
class ApiClient {
  ApiClient({required this.baseUrl});
  final String baseUrl;

  String absoluteUrl(String? url) {
    final v = (url ?? '').trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    final origin = _normalizeBaseUrl(baseUrl);
    if (v.startsWith('/')) return '$origin$v';
    return '$origin/$v';
  }

  dynamic _absolutizeDynamic(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower.startsWith('/uploads/') ||
          lower.startsWith('uploads/') ||
          lower.startsWith('/assets/') ||
          lower.startsWith('assets/') ||
          lower.startsWith('/images/') ||
          lower.startsWith('images/') ||
          lower.startsWith('/')) {
        return absoluteUrl(value);
      }
      return value;
    }
    if (value is List) return value.map(_absolutizeDynamic).toList();
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) => out[k.toString()] = _absolutizeDynamic(v));
      return out;
    }
    return value;
  }

  Map<String, dynamic> _absolutizeMap(Map<String, dynamic> json) {
    final fixed = _absolutizeDynamic(json);
    return (fixed is Map<String, dynamic>) ? fixed : json;
  }

  static String _normalizeBaseUrl(String input) {
    var v = input.trim();
    if (v.isEmpty) return input;
    if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'https://$v';
    v = v.replaceAll(RegExp(r'/+$'), '');
    try {
      final uri = Uri.parse(v);
      return Uri(
              scheme: uri.scheme,
              host: uri.host,
              port: uri.hasPort ? uri.port : null)
          .toString();
    } catch (_) {
      return v;
    }
  }

  T _decode<T>(http.Response res) {
    final body = res.body.trim();
    if (body.isEmpty) {
      if (T == Map<String, dynamic>) return <String, dynamic>{} as T;
      if (T == List<dynamic>) return <dynamic>[] as T;
    }
    try {
      return jsonDecode(body) as T;
    } catch (_) {
      if (T == Map<String, dynamic>) return <String, dynamic>{} as T;
      if (T == List<dynamic>) return <dynamic>[] as T;
      rethrow;
    }
  }

  Uri _u(String path, [Map<String, dynamic>? q]) {
    final uri = Uri.parse(_normalizeBaseUrl(baseUrl)).resolve(path);
    return q == null
        ? uri
        : uri.replace(queryParameters: q.map((k, v) => MapEntry(k, '$v')));
  }

  Future<Map<String, dynamic>> getSettings() async {
    final res = await http.get(_u('/api/public/app-config'));
    if (res.statusCode >= 400) {
      throw Exception('Settings failed: ${res.statusCode}');
    }
    return _absolutizeMap(_decode<Map<String, dynamic>>(res));
  }

  Future<Map<String, dynamic>> getMenu() async {
    final res = await http.get(_u('/api/public/menu'));
    if (res.statusCode >= 400) {
      throw Exception('Menu failed: ${res.statusCode}');
    }
    return _absolutizeMap(_decode<Map<String, dynamic>>(res));
  }

  Future<Map<String, dynamic>> registerCustomer({
    required String name,
    required String phone,
    required double lat,
    required double lng,
    String? address,
  }) async {
    final res = await http.post(
      _u('/api/customer/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'phone': phone,
        'lat': lat,
        'lng': lng,
        'address': address
      }),
    );
    if (res.statusCode >= 400) throw Exception('Register failed: ${res.body}');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<List<dynamic>> listOrders(int customerId) async {
    final res = await http.get(_u('/api/customer/orders/$customerId'));
    if (res.statusCode >= 400) throw Exception('List orders failed');
    return _decode<List<dynamic>>(res);
  }

  Future<Map<String, dynamic>> getOrder(int orderId) async {
    final res = await http.get(_u('/api/customer/order/$orderId'));
    if (res.statusCode >= 400) throw Exception('Get order failed');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<List<dynamic>> listComplaints(int customerId) async {
    final res = await http.get(_u('/api/customer/complaints/$customerId'));
    if (res.statusCode >= 400) throw Exception('List complaints failed');
    return _decode<List<dynamic>>(res);
  }

  Future<Map<String, dynamic>> getComplaint(int threadId) async {
    final res = await http.get(_u('/api/customer/complaint/$threadId'));
    if (res.statusCode >= 400) throw Exception('Get complaint failed');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<List<dynamic>> listNotifications(int customerId,
      {int limit = 50}) async {
    final res = await http
        .get(_u('/api/customer/$customerId/notifications', {'limit': limit}));
    if (res.statusCode >= 400) throw Exception('Notifications failed');
    final json = _decode<Map<String, dynamic>>(res);
    return (json['notifications'] is List)
        ? (json['notifications'] as List)
        : <dynamic>[];
  }

  Future<void> markNotificationRead(int customerId, int notificationId) async {
    final res = await http.post(
      _u('/api/customer/$customerId/notifications/$notificationId/read'),
      headers: {'Content-Type': 'application/json'},
      body: '{}',
    );
    if (res.statusCode >= 400) throw Exception('Mark read failed');
  }

  /// Backend has no coupon codes; stub for UI compatibility.
  Future<Map<String, dynamic>> validateCoupon(
      {required int customerId,
      required String code,
      required double subtotal}) async {
    return {
      'valid': false,
      'message': 'الخصم التلقائي فقط (لا كوبونات)',
      'discount': 0
    };
  }

  Future<int> createOrder({
    required int customerId,
    required List<Map<String, dynamic>> items,
    String? notes,
    String? couponCode,
    int? addressId,
    double? deliveryLat,
    double? deliveryLng,
    String? deliveryAddress,
  }) async {
    final lat = deliveryLat ?? 0.0;
    final lng = deliveryLng ?? 0.0;
    final idempotencyKey =
        '${DateTime.now().millisecondsSinceEpoch}-$customerId';
    final res = await http.post(
      _u('/api/customer/orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'customerId': customerId,
        'idempotencyKey': idempotencyKey,
        'items': items,
        'notes': notes,
        'addressId': addressId,
        'deliveryLat': lat,
        'deliveryLng': lng,
        'deliveryAddress': deliveryAddress ?? '',
      }),
    );
    if (res.statusCode >= 400) throw Exception(res.body);
    final json = _decode<Map<String, dynamic>>(res);
    return json['id'] as int;
  }

  Future<int> createComplaint(
      {required int customerId,
      int? orderId,
      required String title,
      required String message}) async {
    final res = await http.post(
      _u('/api/customer/complaints'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'customerId': customerId,
        'orderId': orderId,
        'title': title,
        'message': message
      }),
    );
    if (res.statusCode >= 400) throw Exception('Create complaint failed');
    final json = _decode<Map<String, dynamic>>(res);
    return json['id'] as int;
  }

  Future<void> sendComplaintMessage(int threadId,
      {required bool fromAdmin, required String message}) async {
    final res = await http.post(
      _u('/api/customer/complaint/$threadId/message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fromAdmin': fromAdmin, 'message': message}),
    );
    if (res.statusCode >= 400) {
      throw Exception('Send message failed: ${res.body}');
    }
  }

  Future<Map<String, dynamic>> rateDriver(
      {required int orderId,
      required int customerId,
      required int stars,
      String? comment}) async {
    final res = await http.post(
      _u('/api/customer/order/$orderId/rate-driver'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'customerId': customerId, 'stars': stars, 'comment': comment}),
    );
    if (res.statusCode >= 400) throw Exception('Rate failed: ${res.body}');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<void> registerFcmCustomer(
      {required int customerId,
      required String token,
      required String platform}) async {
    final res = await http.post(
      _u('/api/public/register-fcm/customer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'userId': customerId, 'token': token, 'platform': platform}),
    );
    if (res.statusCode >= 400) {
      // Don't crash; FCM registration is best-effort
    }
  }
}

/// Admin-only API (FCM register for admin devices).
class AdminApi {
  AdminApi({required this.baseUrl, required this.adminKey});
  final String baseUrl;
  final String adminKey;

  String _u(String path) {
    final b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }

  Future<void> registerFcmAdmin(
      {required String token, required String platform}) async {
    if (adminKey.trim().isEmpty) return;
    final res = await http.post(
      Uri.parse(_u('/api/public/register-fcm/admin')),
      headers: {'Content-Type': 'application/json', 'X-ADMIN-KEY': adminKey},
      body: jsonEncode({'userId': 1, 'token': token, 'platform': platform}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('FCM register failed (${res.statusCode})');
    }
  }
}
