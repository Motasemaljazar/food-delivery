import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'location_queue.dart';

/// Handles sending driver location with offline queue + periodic flush.
class LocationSender {
  LocationSender({required this.api, required this.prefs, required this.driverToken});

  final DriverApi api;
  final SharedPreferences prefs;
  final String driverToken;

  Timer? _flushTimer;

  void startAutoFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 10), (_) => flush());
  }

  void stopAutoFlush() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  Future<void> sendOrQueue({
    required double lat,
    required double lng,
    required double speedMps,
    required double headingDeg,
    required double accuracyMeters,
  }) async {
    // Always attempt immediate send.
    try {
      await api.sendLocation(
        driverToken,
        lat: lat,
        lng: lng,
        speedMps: speedMps,
        headingDeg: headingDeg,
        accuracyMeters: accuracyMeters,
      );
      // If we succeed, also try flushing queued points.
      unawaited(flush());
    } catch (_) {
      // Network failed -> queue it.
      await LocationQueue.enqueue(prefs, {
        'lat': lat,
        'lng': lng,
        'speedMps': speedMps,
        'headingDeg': headingDeg,
        'accuracyMeters': accuracyMeters,
        'ts': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  Future<void> flush() async {
    final batch = LocationQueue.peek(prefs, max: 60);
    if (batch.isEmpty) return;
    try {
      await api.sendLocationBatch(driverToken, batch);
      await LocationQueue.dropFirstN(prefs, batch.length);
    } catch (_) {
      // keep queued
    }
  }
}
