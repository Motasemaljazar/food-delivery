import 'dart:convert';
import 'package:http/http.dart' as http;

class DriverApi {
  DriverApi({required this.baseUrl});
  final String baseUrl;
  Uri _u(String path)=>Uri.parse(baseUrl).resolve(path);

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

  Future<Map<String, dynamic>> login({required String phone, required String pin}) async {
    final res = await http.post(_u('/api/driver/login'), headers: {'Content-Type':'application/json'}, body: jsonEncode({'phone':phone,'pin':pin}));
    if(res.statusCode>=400) throw Exception(res.body);
    return _decode<Map<String, dynamic>>(res);
  }

  Future<Map<String, dynamic>?> currentOrder(String token) async {
    final res = await http.get(_u('/api/driver/current-order'), headers: {'X-DRIVER-TOKEN': token});
    if(res.statusCode==404) return null;
    if(res.statusCode>=400) throw Exception(res.body);
    return _decode<Map<String, dynamic>>(res);
  }

  Future<Map<String, dynamic>> activeOrders(String token) async {
    final res = await http.get(_u('/api/driver/active-orders'), headers: {'X-DRIVER-TOKEN': token});
    if(res.statusCode>=400) throw Exception(res.body);
    return _decode<Map<String, dynamic>>(res);
  }

  Future<void> updateOrderStatus(String token, int orderId, int status) async {
    final res = await http.post(_u('/api/driver/order-status'), headers: {'Content-Type':'application/json','X-DRIVER-TOKEN': token}, body: jsonEncode({'orderId':orderId,'status':status}));
    if(res.statusCode>=400) throw Exception(res.body);
  }

  Future<void> sendLocation(String token, {required double lat, required double lng, required double speedMps, required double headingDeg, required double accuracyMeters}) async {
    final res = await http.post(
      _u('/api/driver/location'),
      headers: {'Content-Type':'application/json','X-DRIVER-TOKEN': token},
      body: jsonEncode({'lat':lat,'lng':lng,'speedMps':speedMps,'headingDeg':headingDeg,'accuracyMeters':accuracyMeters}),
    );
    if(res.statusCode>=400) throw Exception(res.body);
  }

  Future<void> sendLocationBatch(String token, List<Map<String, dynamic>> points) async {
    final res = await http.post(
      _u('/api/driver/location/batch'),
      headers: {'Content-Type':'application/json','X-DRIVER-TOKEN': token},
      body: jsonEncode({'points': points}),
    );
    if(res.statusCode>=400) throw Exception(res.body);
  }

  Future<void> registerFcmDriver(String driverToken, {required String token, required String platform}) async {
    final res = await http.post(
      _u('/api/public/register-fcm/driver'),
      headers: {'Content-Type':'application/json','X-DRIVER-TOKEN': driverToken},
      body: jsonEncode({'userId': 0, 'token': token, 'platform': platform}),
    );
    if (res.statusCode >= 400) {
      // ignore
    }
  }

  Future<Map<String, dynamic>> publicSettings() async {
    final res = await http.get(_u('/api/public/settings'));
    if (res.statusCode >= 400) throw Exception('settings_failed');
    return _decode<Map<String, dynamic>>(res);
  }


  Future<void> cancelOrder(String token, {required int orderId, String? reason}) async {
    final res = await http.post(
      _u('/api/driver/order/$orderId/cancel'),
      headers: {'Content-Type':'application/json','X-DRIVER-TOKEN': token},
      body: jsonEncode({'reason': reason}),
    );
    if (res.statusCode >= 400) {
      final body = res.body.trim();
      try {
        final j = jsonDecode(body);
        throw Exception(j['message'] ?? j['error'] ?? 'cancel_failed');
      } catch (_) {
        throw Exception('cancel_failed');
      }
    }
  }



  Future<Map<String, dynamic>> todayStats(String token) async {
    final res = await http.get(_u('/api/driver/today-stats'), headers: {'X-DRIVER-TOKEN': token});
    if(res.statusCode>=400) throw Exception(res.body);
    return _decode<Map<String, dynamic>>(res);
  }

}
