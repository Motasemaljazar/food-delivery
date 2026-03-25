import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import '../services/push.dart';
import 'register_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.prefs, required this.state});
  final SharedPreferences prefs;
  final AppState state;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final String baseUrl;
  Map<String, dynamic>? settings;
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    baseUrl = kBackendBaseUrl;
    _init();
  }

  Future<void> _init() async {
    try {
      final api = ApiClient(baseUrl: baseUrl);
      settings = await api.getSettings();
      if (settings != null) {
        widget.state.setConfig(settings!);
      }
    } catch (_) {
      // Ignore for offline local start
    }

    // Two-step splash backgrounds (5-6 seconds total)
    final bgs = widget.state.splashBackgrounds;
    if (bgs.isNotEmpty) {
      setState(() => _phase = 1);
      await Future.delayed(const Duration(seconds: 3));
      if (bgs.length > 1) {
        setState(() => _phase = 2);
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    final cid = widget.prefs.getInt('customerId');
    final name = widget.prefs.getString('customerName');
    final phone = widget.prefs.getString('customerPhone');
    final lat = widget.prefs.getDouble('defaultLat');
    final lng = widget.prefs.getDouble('defaultLng');
    final addr = widget.prefs.getString('defaultAddress');

    if (cid != null && name != null && phone != null && lat != null && lng != null) {
      widget.state.setCustomer(id: cid, name: name, phone: phone, lat: lat, lng: lng, address: addr);
      try {
        await PushService(api: ApiClient(baseUrl: baseUrl), platformTag: 'android').initForCustomer(customerId: cid);
      } catch (_) {}
      if (mounted) Navigator.of(context).pushReplacementNamed(HomeScreen.route);
    } else {
      if (mounted) Navigator.of(context).pushReplacementNamed(RegisterScreen.route);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? logo = widget.state.logoUrl;
    if (logo != null && logo.startsWith('/')) {
      // Build absolute URL and bust cache in dev
      logo = '$baseUrl$logo?v=${DateTime.now().millisecondsSinceEpoch}';
    }

    final bgs = widget.state.splashBackgrounds;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (bgs.isNotEmpty && _phase > 0)
            Image.network(
              bgs[_phase == 1 ? 0 : (bgs.length > 1 ? 1 : 0)],
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null)
                  Image.network(logo, height: 72, errorBuilder: (_, __, ___) => const Icon(Icons.delivery_dining, size: 72))
                else
                  const Icon(Icons.delivery_dining, size: 72),
                const SizedBox(height: 12),
                Text(widget.state.restaurantName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
