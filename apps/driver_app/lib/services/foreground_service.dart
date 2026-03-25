import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'foreground_location_task.dart';

/// Start/stop Android foreground service for stable tracking.
class DriverForegroundService {
  static Future<void> ensureRunning() async {
    if (kIsWeb) return;
    final running = await FlutterForegroundTask.isRunningService;
    if (running) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'تتبع السائق يعمل',
      notificationText: 'جاري تشغيل التتبع بالخلفية…',
      callback: startDriverForegroundService,
    );
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    final running = await FlutterForegroundTask.isRunningService;
    if (!running) return;
    await FlutterForegroundTask.stopService();
  }
}
