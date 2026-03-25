import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Offline queue for driver location points.
///
/// Goal: if internet drops, we keep points locally and flush later.
/// This is a lightweight, no-service approach (still uses same REST APIs).
class LocationQueue {
  static const _key = 'driver_location_queue_v1';

  static Future<void> enqueue(SharedPreferences prefs, Map<String, dynamic> point) async {
    final raw = prefs.getString(_key);
    final List<dynamic> arr = raw == null ? <dynamic>[] : (jsonDecode(raw) as List<dynamic>);

    arr.add(point);

    // Hard cap to avoid uncontrolled growth (approx 15 minutes @ 3s interval ~= 300 points)
    const max = 600;
    if (arr.length > max) {
      arr.removeRange(0, arr.length - max);
    }
    await prefs.setString(_key, jsonEncode(arr));
  }

  static List<Map<String, dynamic>> peek(SharedPreferences prefs, {int max = 50}) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    final List<dynamic> arr = jsonDecode(raw) as List<dynamic>;
    return arr.take(max).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> dropFirstN(SharedPreferences prefs, int n) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return;
    final List<dynamic> arr = jsonDecode(raw) as List<dynamic>;
    if (n <= 0) return;
    if (n >= arr.length) {
      await prefs.remove(_key);
      return;
    }
    arr.removeRange(0, n);
    await prefs.setString(_key, jsonEncode(arr));
  }

  static int count(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return 0;
    try {
      return (jsonDecode(raw) as List).length;
    } catch (_) {
      return 0;
    }
  }
}
