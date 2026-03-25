import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../services/api.dart';
import '../services/push.dart';
import '../services/foreground_service.dart';
import '../models/brand_state.dart';

class DriverSplash extends StatefulWidget {
  const DriverSplash({super.key, required this.prefs, required this.brand});
  final SharedPreferences prefs;
  final BrandState brand;

  @override
  State<DriverSplash> createState() => _DriverSplashState();
}

class _DriverSplashState extends State<DriverSplash> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final token = widget.prefs.getString('driverToken');
      if(token != null && token.isNotEmpty) {
        try { await DriverForegroundService.ensureRunning(); } catch (_) {}
        final baseUrl = kBackendBaseUrl;
        // Load public restaurant settings (branding + routing profile) and cache locally.
        try {
          final s = await DriverApi(baseUrl: baseUrl).publicSettings();
          await widget.brand.setConfig(s);
          if (s['routingProfile'] != null) await widget.prefs.setString('routingProfile', s['routingProfile'].toString());
        } catch (_) {}
        try {
          await DriverPushService(api: DriverApi(baseUrl: baseUrl), platformTag: 'android').initForDriver(driverToken: token);
        } catch (_) {}
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_)=>DriverHome(prefs: widget.prefs, brand: widget.brand)),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_)=>DriverLogin(prefs: widget.prefs, brand: widget.brand)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
