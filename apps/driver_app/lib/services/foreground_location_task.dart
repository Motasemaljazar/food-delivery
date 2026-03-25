import 'dart:async';
import 'dart:isolate';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';

import 'api.dart';
import 'location_sender.dart';

/// Foreground-service task for stable tracking on Android 12+.
///
/// Runs even when the app is backgrounded, as long as the foreground notification is alive.
class DriverForegroundTaskHandler extends TaskHandler {
  SharedPreferences? _prefs;
  LocationSender? _sender;
  Timer? _timer;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _prefs = await SharedPreferences.getInstance();
    final token = _prefs!.getString('driverToken');
    final baseUrl = kBackendBaseUrl;
    if (token == null || token.trim().isEmpty) return;

    final api = DriverApi(baseUrl: baseUrl);
    _sender = LocationSender(api: api, prefs: _prefs!, driverToken: token);
    _sender!.startAutoFlush();

    // Small periodic loop. We intentionally keep it modest to protect battery.
    _timer = Timer.periodic(const Duration(seconds: 8), (_) async {
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (!enabled) return;
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
            .timeout(const Duration(seconds: 8));
        final gpsMps = pos.speed.isFinite ? pos.speed : 0.0;
        await _sender!.sendOrQueue(
          lat: pos.latitude,
          lng: pos.longitude,
          speedMps: (gpsMps >= 0) ? gpsMps : 0,
          headingDeg: pos.heading.isFinite ? pos.heading : 0,
          accuracyMeters: pos.accuracy.isFinite ? pos.accuracy : 0,
        );

        // Update notification text
        await FlutterForegroundTask.updateService(
          notificationTitle: 'تتبع السائق يعمل',
          notificationText: 'آخر تحديث: ${DateTime.now().toLocal().toString().substring(11, 19)}',
        );
      } catch (_) {
        // ignore transient errors
      }
    });
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    // Not used (we use our own timer).
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    _timer?.cancel();
    _sender?.stopAutoFlush();
  }
}

/// Entry point required by the plugin.
@pragma('vm:entry-point')
void startDriverForegroundService() {
  FlutterForegroundTask.setTaskHandler(DriverForegroundTaskHandler());
}
