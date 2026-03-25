import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// استدعاءات API لوحة التحكم مع رأس X-ADMIN-KEY (للتطبيق الأصلي على أندرويد).
class AdminApiService {
  AdminApiService({required this.baseUrl, required this.adminKey});
  final String baseUrl;
  final String adminKey;

  String _path(String p) {
    final b = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return p.startsWith('/') ? '$b$p' : '$b/$p';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-ADMIN-KEY': adminKey,
      };

  Future<T> _get<T>(String path, T Function(dynamic) fromJson) async {
    final res = await http.get(Uri.parse(_path(path)), headers: _headers);
    if (res.statusCode >= 400) throw AdminApiException(res.statusCode, res.body);
    final decoded = jsonDecode(res.body);
    return fromJson(decoded);
  }

  Future<T> _post<T>(String path, [Object? body]) async {
    final res = await http.post(
      Uri.parse(_path(path)),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode >= 400) throw AdminApiException(res.statusCode, res.body);
    if (res.body.trim().isEmpty) return {} as T;
    return jsonDecode(res.body) as T;
  }

  Future<void> _postVoid(String path, [Object? body]) async {
    final res = await http.post(
      Uri.parse(_path(path)),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode >= 400) throw AdminApiException(res.statusCode, res.body);
  }

  /// التحقق من أن المفتاح صالح (طلب بسيط للإعدادات).
  Future<bool> checkKey() async {
    try {
      await getSettings();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getSettings() async {
    return _get<Map<String, dynamic>>('/api/admin/settings', (d) => Map<String, dynamic>.from(d as Map));
  }

  Future<void> updateSettings(Map<String, dynamic> payload) async {
    await _postVoid('/api/admin/settings', payload);
  }

  /// رفع صورة (شعار أو غيرها). kind مثل: logo, banner, closed
  /// يعيد الرابط الكامل للصورة المرفوعة.
  Future<String> uploadAsset(File file, {String kind = 'logo'}) async {
    final uri = Uri.parse(_path('/api/admin/upload/asset')).replace(queryParameters: {'kind': kind});
    final request = http.MultipartRequest('POST', uri);
    request.headers['X-ADMIN-KEY'] = adminKey;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) throw AdminApiException(res.statusCode, res.body);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final path = data['url'] as String?;
    if (path == null || path.isEmpty) throw AdminApiException(res.statusCode, res.body);
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return path.startsWith('http') ? path : '$base$path';
  }

  Future<List<dynamic>> getOrders() async {
    return _get<List<dynamic>>('/api/admin/orders', (d) => List<dynamic>.from(d as List));
  }

  Future<Map<String, dynamic>> getOrder(int id) async {
    return _get<Map<String, dynamic>>('/api/admin/order/$id', (d) => Map<String, dynamic>.from(d as Map));
  }

  Future<List<dynamic>> getDrivers() async {
    return _get<List<dynamic>>('/api/admin/drivers', (d) => List<dynamic>.from(d as List));
  }

  Future<void> assignDriver(int orderId, int? driverId) async {
    await _post('/api/admin/assign-driver', {'orderId': orderId, 'driverId': driverId});
  }

  Future<void> setOrderEta(int orderId, int? prepEtaMinutes, int? deliveryEtaMinutes) async {
    await _postVoid('/api/admin/order-eta', {
      'orderId': orderId,
      'prepEtaMinutes': prepEtaMinutes,
      'deliveryEtaMinutes': deliveryEtaMinutes,
    });
  }

  Future<void> cancelOrder(int orderId) async {
    await _postVoid('/api/admin/order/$orderId/cancel');
  }

  Future<void> updateOrderDeliveryFee(int orderId, double? deliveryFee) async {
    final o = await getOrder(orderId);
    final items = (o['items'] as List?)?.map((i) {
      final m = i as Map;
      return {'productId': m['productId'], 'quantity': m['quantity'], 'optionsSnapshot': m['optionsSnapshot']};
    }).toList() ?? [];
    final res = await http.post(
      Uri.parse(_path('/api/admin/order/$orderId/edit')),
      headers: _headers,
      body: jsonEncode({
        'items': items,
        'notes': o['notes'],
        'deliveryAddress': o['deliveryAddress'],
        'deliveryLat': o['deliveryLat'],
        'deliveryLng': o['deliveryLng'],
        if (deliveryFee != null) 'deliveryFee': deliveryFee,
      }),
    );
    if (res.statusCode >= 400) throw AdminApiException(res.statusCode, res.body);
  }

  // ——— التقارير ———
  Future<Map<String, dynamic>> getReportsSummary() async {
    return _get<Map<String, dynamic>>('/api/admin/reports/summary', (d) => Map<String, dynamic>.from(d as Map));
  }

  Future<Map<String, dynamic>> getReportsWeeklySummary() async {
    return _get<Map<String, dynamic>>('/api/admin/reports/weekly-summary', (d) => Map<String, dynamic>.from(d as Map));
  }

  Future<Map<String, dynamic>> getReportsMonthlySummary() async {
    return _get<Map<String, dynamic>>('/api/admin/reports/monthly-summary', (d) => Map<String, dynamic>.from(d as Map));
  }

  Future<List<dynamic>> getReportsProductsDaily() async {
    return _get<List<dynamic>>('/api/admin/reports/products-daily', (d) => List<dynamic>.from(d as List));
  }

  Future<List<dynamic>> getReportsDriversDaily() async {
    return _get<List<dynamic>>('/api/admin/reports/drivers-daily', (d) => List<dynamic>.from(d as List));
  }

  Future<Map<String, dynamic>> getReportsTop() async {
    return _get<Map<String, dynamic>>('/api/admin/reports/top', (d) => Map<String, dynamic>.from(d as Map));
  }

  // ——— الخريطة الحية ———
  Future<Map<String, dynamic>> getLiveMapData() async {
    return _get<Map<String, dynamic>>('/api/admin/live-map', (d) => Map<String, dynamic>.from(d as Map));
  }
}

class AdminApiException implements Exception {
  AdminApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  String get message => statusCode == 401 ? 'مفتاح الإدارة غير صحيح' : body;
}
