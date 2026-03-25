import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl});
  final String baseUrl;

  /// Build an absolute URL for images/static files returned as relative paths.
  /// Backend often returns values like `/uploads/...`.
  /// On Flutter Web, `Image.network("/uploads/x")` resolves against the *web app* origin,
  /// not the backend origin, so images appear broken.
  String absoluteUrl(String? url) {
    final v = (url ?? '').trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    final origin = normalizeBaseUrl(baseUrl);
    if (v.startsWith('/')) return origin + v;
    return origin + '/' + v;
  }

  dynamic _absolutizeDynamic(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      // Only absolutize obvious static-file paths.
      // IMPORTANT: بعض البيانات قد تكون بدون / في البداية (مثال: uploads/products/...).
      final lower = value.toLowerCase();
      if (lower.startsWith('/uploads/') || lower.startsWith('uploads/') ||
          lower.startsWith('/assets/')  || lower.startsWith('assets/')  ||
          lower.startsWith('/images/')  || lower.startsWith('images/')  ||
          lower.startsWith('/')) {
        return absoluteUrl(value);
      }
      return value;
    }
    if (value is List) {
      return value.map(_absolutizeDynamic).toList();
    }
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        final key = k.toString();
        // Common URL keys
        if (v is String && (key.toLowerCase().endsWith('url') || key.toLowerCase().contains('image'))) {
          out[key] = _absolutizeDynamic(v);
        } else {
          out[key] = _absolutizeDynamic(v);
        }
      });
      return out;
    }
    return value;
  }

  Map<String, dynamic> _absolutizeMap(Map<String, dynamic> json) {
    final fixed = _absolutizeDynamic(json);
    return (fixed is Map<String, dynamic>) ? fixed : json;
  }

  /// Normalize common local dev URLs.
  /// Default local backend API URL for this project: https://localhost:5101
  static String normalizeBaseUrl(String input) {
    var v = input.trim();
    if (v.isEmpty) return 'https://localhost:5101';

    // Auto-add scheme if missing.
    if (!v.startsWith('http://') && !v.startsWith('https://')) {
      v = 'http://$v';
    }

    // Local dev (Visual Studio) typically serves HTTPS on 5101.

    // Remove trailing slashes.
    v = v.replaceAll(RegExp(r'/+$'), '');

    // If user pasted an Admin dashboard URL like:
    //   http://localhost:5101/Admin/Orders
    // strip path and redirect to API port (5249).
    try {
      final uri = Uri.parse(v);
      var scheme = uri.scheme;
      var host = uri.host;
      var port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);

      // Strip any path/query/fragment (keep only origin).
      // Special-case local dev: if user pasted an Admin dashboard deep link,
      // keep the same origin (5101) and just strip the path.
      // Prefer HTTPS on 5101 (default Visual Studio profile).
      if ((host == 'localhost' || host == '127.0.0.1') && port == 5101) {
        scheme = uri.scheme.isNotEmpty ? uri.scheme : 'https';
        if (scheme != 'http' && scheme != 'https') scheme = 'https';
      }

      final origin = Uri(scheme: scheme, host: host, port: port).toString();
      return origin;
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
    final uri = Uri.parse(normalizeBaseUrl(baseUrl)).resolve(path);
    return q == null ? uri : uri.replace(queryParameters: q.map((k,v)=>MapEntry(k, '$v')));
  }

  Future<Map<String, dynamic>> getSettings() async {
    final res = await http.get(_u('/api/public/app-config'));
    if(res.statusCode>=400) throw Exception('Settings failed: ${res.statusCode}');
    return _absolutizeMap(_decode<Map<String, dynamic>>(res));
  }

  Future<Map<String, dynamic>> getMenu() async {
    final res = await http.get(_u('/api/public/menu'));
    if(res.statusCode>=400) throw Exception('Menu failed: ${res.statusCode}');
    return _absolutizeMap(_decode<Map<String, dynamic>>(res));
  }

  /// تقدير رسوم التوصيل لموقع (lat, lng) — يُستدعى بعد تعيين الموقع لتحديث السلة قبل إرسال الطلب.
  Future<Map<String, dynamic>> deliveryEstimate(double lat, double lng) async {
    final res = await http.get(_u('/api/public/delivery-estimate', {'lat': lat.toString(), 'lng': lng.toString()}));
    if (res.statusCode >= 400) throw Exception(res.body);
    return _decode<Map<String, dynamic>>(res);
  }

  Future<List<dynamic>> getOfferItems(int offerId) async {
    final res = await http.get(_u('/api/public/offers/$offerId/items'));
    if (res.statusCode >= 400) throw Exception('Offer items failed: ${res.statusCode}');
    final json = _absolutizeMap(_decode<Map<String, dynamic>>(res));
    final items = (json['items'] is List) ? (json['items'] as List) : <dynamic>[];
    return items.map(_absolutizeDynamic).toList();
  }

  Future<Map<String, dynamic>> registerCustomer({required String name, required String phone, required double lat, required double lng, String? address}) async {
    final res = await http.post(_u('/api/customer/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name':name,'phone':phone,'lat':lat,'lng':lng,'address':address}),
    );
    if(res.statusCode>=400) throw Exception('Register failed: ${res.body}');
    return _decode<Map<String, dynamic>>(res);
  }

  /// Firebase: check if current Firebase user already has a customer record.
  /// Returns either:
  /// - { exists: true, customer: {...} }
  /// - { exists: false, suggestedName: '...' }
  /// على 403 قد يعيد السيرفر { error: 'customer_blocked', message: '...' } — يجب على المتصل التحقق من session['error'].
  Future<Map<String, dynamic>> firebaseCustomerSession({required String idToken}) async {
    final res = await http.post(
      _u('/api/customer/firebase/session'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
    final j = _decode<Map<String, dynamic>>(res);
    if (res.statusCode == 403) {
      // إرجاع الـ body ليتحقق المتصل من customer_blocked عند إعادة فتح التطبيق
      return j;
    }
    if (res.statusCode >= 400) throw Exception('Auth failed: ${res.body}');
    return j;
  }

  /// Firebase: create/update customer profile (name + default location).
  Future<Map<String, dynamic>> firebaseRegisterCustomer({
    required String idToken,
    required String name,
    required String phone,
    required double lat,
    required double lng,
    String? address,
  }) async {
    final res = await http.post(
      _u('/api/customer/firebase/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken, 'name': name, 'phone': phone, 'lat': lat, 'lng': lng, 'address': address}),
    );
    if (res.statusCode == 403) {
      final j = _decode<Map<String, dynamic>>(res);
      throw Exception((j['message'] ?? 'تم منعك من الدخول') as String);
    }
    if (res.statusCode >= 400) throw Exception('فشل حفظ الحساب: ${res.body}');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<int> createOrder({
    required int customerId,
    required String idempotencyKey,
    required List<Map<String, dynamic>> items,
    String? notes,
    int? addressId,
    required double deliveryLat,
    required double deliveryLng,
    String? deliveryAddress,
  }) async {
    final res = await http.post(_u('/api/customer/orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'customerId': customerId,
        'idempotencyKey': idempotencyKey,
        'items': items,
        'notes': notes,
        'addressId': addressId,
        'deliveryLat': deliveryLat,
        'deliveryLng': deliveryLng,
        'deliveryAddress': deliveryAddress,
      }),
    );
    if(res.statusCode>=400) throw Exception('تعذر إنشاء الطلب: ${res.body}');
    final json = _decode<Map<String, dynamic>>(res);
    return json['id'] as int;
  }




Future<List<dynamic>> getAddresses(int customerId) async {
  final res = await http.get(_u('/api/customer/addresses/$customerId'));
  if(res.statusCode>=400) throw Exception('Get addresses failed');
  return _decode<List<dynamic>>(res);
}

Future<Map<String, dynamic>> createAddress(Map<String, dynamic> payload) async {
  final res = await http.post(_u('/api/customer/addresses'),
    headers: {'Content-Type':'application/json'},
    body: jsonEncode(payload),
  );
  if(res.statusCode>=400) throw Exception(res.body);
  return _decode<Map<String, dynamic>>(res);
}

Future<Map<String, dynamic>> updateAddress(int id, Map<String, dynamic> payload) async {
  final res = await http.put(_u('/api/customer/addresses/$id'),
    headers: {'Content-Type':'application/json'},
    body: jsonEncode(payload),
  );
  if(res.statusCode>=400) throw Exception(res.body);
  return _decode<Map<String, dynamic>>(res);
}

Future<void> deleteAddress(int id, int customerId) async {
  final res = await http.delete(_u('/api/customer/addresses/$id?customerId=$customerId'));
  if(res.statusCode>=400) throw Exception(res.body);
}

Future<void> setDefaultAddress(int id, int customerId) async {
  final res = await http.post(_u('/api/customer/addresses/$id/set-default?customerId=$customerId'));
  if(res.statusCode>=400) throw Exception(res.body);
}

  Future<List<dynamic>> listOrders(int customerId) async {
    final res = await http.get(_u('/api/customer/orders/$customerId'));
    if(res.statusCode>=400) throw Exception('List orders failed');
    return _decode<List<dynamic>>(res);
  }

  Future<Map<String, dynamic>> getOrder(int orderId) async {
    final res = await http.get(_u('/api/customer/order/$orderId'));
    if(res.statusCode>=400) throw Exception('Get order failed');
    return _decode<Map<String, dynamic>>(res);
  }

  
  Future<void> submitOrderRating({
    required int orderId,
    required int customerId,
    required int restaurantRate,
    required int driverRate,
    String? comment,
  }) async {
    final res = await http.post(
      _u('/api/ratings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'orderId': orderId,
        'customerId': customerId,
        'restaurantRate': restaurantRate,
        'driverRate': driverRate,
        'comment': comment,
      }),
    );
    if (res.statusCode >= 400) throw Exception('فشل حفظ التقييم: ${res.body}');
  }

  Future<void> editOrder({
    required int orderId,
    required int customerId,
    required List<Map<String, dynamic>> items,
    String? notes,
    double? deliveryLat,
    double? deliveryLng,
    String? deliveryAddress,
  }) async {
    final res = await http.post(
      _u('/api/customer/order/$orderId/edit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'customerId': customerId,
        'items': items,
        'notes': notes,
        'deliveryLat': deliveryLat,
        'deliveryLng': deliveryLng,
        'deliveryAddress': deliveryAddress,
      }),
    );
    if (res.statusCode >= 400) throw Exception('تعذر تعديل الطلب: ${res.body}');
  }

Future<Map<String, dynamic>> getPendingRating(int customerId) async {
    final res = await http.get(_u('/api/customer/pending-rating/$customerId'));
    if (res.statusCode >= 400) throw Exception('Pending rating failed');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<Map<String, dynamic>> rateDriver({required int orderId, required int customerId, required int stars, String? comment}) async {
    final res = await http.post(
      _u('/api/customer/order/$orderId/rate-driver'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'customerId': customerId, 'stars': stars, 'comment': comment}),
    );
    if (res.statusCode >= 400) throw Exception('Rate failed: ${res.body}');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<Map<String, dynamic>> rateRestaurant({required int orderId, required int customerId, required int stars, String? comment}) async {
    final res = await http.post(
      _u('/api/customer/order/$orderId/rate-restaurant'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'customerId': customerId, 'stars': stars, 'comment': comment}),
    );
    if (res.statusCode >= 400) throw Exception('Rate failed: ${res.body}');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<int> createComplaint({required int customerId, int? orderId, required String title, required String message}) async {
    final res = await http.post(_u('/api/customer/complaints'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'customerId':customerId,'orderId':orderId,'title':title,'message':message}),
    );
    if(res.statusCode>=400) throw Exception('Create complaint failed');
    final json = _decode<Map<String, dynamic>>(res);
    return json['id'] as int;
  }

  Future<List<dynamic>> listComplaints(int customerId) async {
    final res = await http.get(_u('/api/customer/complaints/$customerId'));
    if(res.statusCode>=400) throw Exception('List complaints failed');
    return _decode<List<dynamic>>(res);
  }

  Future<Map<String, dynamic>> getOrCreateChatThread(int customerId) async {
    final res = await http.get(_u('/api/customer/chat-thread/$customerId'));
    if (res.statusCode >= 400) throw Exception('Get chat thread failed: ${res.body}');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<Map<String, dynamic>> getComplaint(int threadId) async {
    final res = await http.get(_u('/api/customer/complaint/$threadId'));
    if(res.statusCode>=400) throw Exception('Get complaint failed');
    return _decode<Map<String, dynamic>>(res);
  }

  Future<void> sendComplaintMessage(int threadId, {required bool fromAdmin, required String message}) async {
    final res = await http.post(_u('/api/customer/complaint/$threadId/message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fromAdmin':fromAdmin,'message':message}),
    );
    if(res.statusCode>=400) throw Exception('Send message failed: ${res.body}');
  }

  Future<List<dynamic>> listNotifications(int customerId, {int limit = 50}) async {
    final res = await http.get(_u('/api/customer/$customerId/notifications', {'limit': limit}));
    if (res.statusCode >= 400) throw Exception('Notifications failed');
    final json = _decode<Map<String, dynamic>>(res);
    return (json['notifications'] is List) ? (json['notifications'] as List) : <dynamic>[];
  }

  Future<void> markNotificationRead(int customerId, int notificationId) async {
    final res = await http.post(_u('/api/customer/$customerId/notifications/$notificationId/read'), headers: {'Content-Type': 'application/json'}, body: '{}');
    if (res.statusCode >= 400) throw Exception('Mark read failed');
  }

  Future<void> registerFcmCustomer({required int customerId, required String token, required String platform}) async {
    final res = await http.post(
      _u('/api/public/register-fcm/customer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': customerId, 'token': token, 'platform': platform}),
    );
    // Don't crash app if FCM registration fails.
    if (res.statusCode >= 400) {
      // ignore
    }
  }


  Future<void> cancelOrder({required int orderId, required int customerId, required String reason}) async {
    final res = await http.post(
      _u('/api/customer/order/$orderId/cancel'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'customerId': customerId, 'reason': reason}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_decode(res)['message'] ?? _decode(res)['error'] ?? 'cancel_failed');
    }
  }

}
