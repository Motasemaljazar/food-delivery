import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import '../services/push.dart';
import '../services/realtime.dart';
import 'onboarding_screen.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'closed_screen.dart';
import 'blocked_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../app_config.dart';

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
    // 1) Load cached settings immediately (fast startup / offline)
    try {
      final cached = widget.prefs.getString('cached_settings');
      if (cached != null && cached.trim().isNotEmpty) {
        final json = jsonDecode(cached) as Map<String, dynamic>;
        widget.state.setConfig(json);
      }
    } catch (_) {}

    // 2) Keep listening for settings changes (admin updates)
    try {
      final rt = RealtimeClient(baseUrl: baseUrl);
      await rt.connectPublic(onSettingsUpdated: () async {
        try {
          final api = ApiClient(baseUrl: baseUrl);
          final s = await api.getSettings();
          widget.state.setConfig(s);
          await widget.prefs.setString('cached_settings', jsonEncode(s));
        } catch (_) {}
      });
    } catch (_) {}

    try {
      final api = ApiClient(baseUrl: baseUrl);
      settings = await api.getSettings();
      if (settings != null) {
        widget.state.setConfig(settings!);
        try {
          await widget.prefs.setString('cached_settings', jsonEncode(settings));
        } catch (_) {}
      }
    } catch (_) {
      // Ignore for offline local start
    }

    // Hard block if restaurant is manually closed (web + android)
    if (!widget.state.isAcceptingOrders) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => _ClosedGate(
            baseUrl: baseUrl,
            prefs: widget.prefs,
            state: widget.state,
          ),
        ),
      );
      return;
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

    // First run onboarding
    final seen = widget.prefs.getBool('seenOnboarding') ?? false;
    if (!seen) {
      if (mounted)
        Navigator.of(context).pushReplacementNamed(OnboardingScreen.route);
      return;
    }

    // If user already authenticated with Firebase and has customerId saved, go home.
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final cid = widget.prefs.getInt('customerId');
    final name = widget.prefs.getString('customerName');
    final phone = widget.prefs.getString('customerPhone') ?? '';
    final lat = widget.prefs.getDouble('defaultLat');
    final lng = widget.prefs.getDouble('defaultLng');
    final addr = widget.prefs.getString('defaultAddress');

    if (firebaseUser != null &&
        cid != null &&
        name != null &&
        lat != null &&
        lng != null) {
      // التحقق من البريد مطلوب فقط لحساب البريد/كلمة المرور وليس لـ Google
      final isGoogleUser = firebaseUser.providerData.any((p) => p.providerId == 'google.com');
      if (!isGoogleUser && !firebaseUser.emailVerified) {
        try { await FirebaseAuth.instance.signOut(); } catch (_) {}
        if (mounted) Navigator.of(context).pushReplacementNamed(AuthScreen.route);
        return;
      }
      // التحقق من حالة الحظر عند كل فتح للتطبيق (حتى بعد الخروج والعودة)
      try {
        final api = ApiClient(baseUrl: baseUrl);
        final token = await firebaseUser.getIdToken();
        if (token != null) {
          final session = await api.firebaseCustomerSession(idToken: token);
          if (session.containsKey('error') &&
              session['error'] == 'customer_blocked') {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => BlockedScreen(
                    prefs: widget.prefs,
                    state: widget.state,
                  ),
                ),
              );
            }
            return;
          }
          // إذا لم تكن الجلسة صالحة (مثلاً لا يوجد id) فلا نكمل إلى Home
          if (session['id'] == null) {
            if (mounted) Navigator.of(context).pushReplacementNamed(AuthScreen.route);
            return;
          }
        }
      } catch (_) {
        // في حالة خطأ شبكة نتابع عادياً لتجنب منع الدخول بسبب انقطاع مؤقت
      }

      widget.state.setCustomer(
          id: cid, name: name, phone: phone, lat: lat, lng: lng, address: addr);
      try {
        await PushService(
                api: ApiClient(baseUrl: baseUrl), platformTag: 'android')
            .initForCustomer(customerId: cid);
      } catch (_) {}
      if (mounted) Navigator.of(context).pushReplacementNamed(HomeScreen.route);
    } else {
      if (mounted) Navigator.of(context).pushReplacementNamed(AuthScreen.route);
    }
  }

  @override
  Widget build(BuildContext context) {
    // رابط ثابت بدون ?v= حتى لا يُعاد تحميل الصورة عند كل إعادة بناء فيختفي اللوغو
    String? logo = widget.state.logoUrl;
    if (logo != null && logo.startsWith('/')) {
      logo = '$baseUrl$logo';
    }

    final bgs = widget.state.splashBackgrounds;
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // خلفية متدرجة احترافية
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFD32F2F),
                  const Color(0xFFFF6F00),
                  const Color(0xFFFF9800),
                ],
              ),
            ),
          ),

          // صورة الخلفية إن وجدت
          if (bgs.isNotEmpty && _phase > 0)
            Opacity(
              opacity: 0.3,
              child: Image.network(
                bgs[_phase == 1 ? 0 : (bgs.length > 1 ? 1 : 0)],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),

          // طبقة شفافة للتحكم بالسطوع
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.1),
                ],
              ),
            ),
          ),

          // المحتوى الرئيسي
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الشعار مع خلفية دائرية
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: logo != null
                      ? ClipOval(
                          child: Image.network(
                            logo,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                    ? child
                                    : const Center(
                                        child: SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                                Color(0xFFD32F2F)),
                                          ),
                                        ),
                                      ),
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.restaurant_menu,
                              size: 60,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.restaurant_menu,
                          size: 60,
                          color: Color(0xFFD32F2F),
                        ),
                ),
                const SizedBox(height: 24),

                // اسم المطعم
                Text(
                  widget.state.restaurantName,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.3),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // شعار أو وصف قصير
                Text(
                  'طعم لا يُقاوم',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 40),

                // مؤشر التحميل الاحترافي
                Container(
                  width: 50,
                  height: 50,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosedGate extends StatelessWidget {
  const _ClosedGate(
      {required this.baseUrl, required this.prefs, required this.state});
  final String baseUrl;
  final SharedPreferences prefs;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ClosedScreen(
        state: state,
        onRefresh: () async {
          try {
            final api = ApiClient(baseUrl: baseUrl);
            final s = await api.getSettings();
            state.setConfig(s);
            try {
              await prefs.setString('cached_settings', jsonEncode(s));
            } catch (_) {}
            final open = state.isAcceptingOrders;
            if (open && context.mounted) {
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                  builder: (_) => SplashScreen(prefs: prefs, state: state)));
            }
            return open;
          } catch (_) {
            return false;
          }
        },
      ),
    );
  }
}
