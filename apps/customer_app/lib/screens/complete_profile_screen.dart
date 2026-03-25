import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../app_config.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import '../widgets/brand_title.dart';
import '../services/push.dart';
import 'home_screen.dart';
// No map UI for customer (requirement: GPS only)

class CompleteProfileScreen extends StatefulWidget {
  static const route = '/complete-profile';
  const CompleteProfileScreen({
    super.key,
    required this.prefs,
    required this.state,
    this.email,
    this.suggestedName,
  });
  final SharedPreferences prefs;
  final AppState state;
  final String? email;
  final String? suggestedName;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  double? lat;
  double? lng;
  String? address;
  bool loading = false;
  String? error;

  String get baseUrl => kBackendBaseUrl;

  @override
  void initState() {
    super.initState();
    final s = (widget.suggestedName ?? '').trim();
    _name.text = s.isEmpty ? 'زبون' : s;
    _phone.text = (widget.prefs.getString('customerPhone') ?? '').trim();

    // Auto GPS on first run
    _initGps();
  }

  Future<void> _initGps() async {
    try {
      final pos = await _getCurrentPositionOrThrow();
      if (!mounted) return;
      setState(() {
        lat = pos.latitude;
        lng = pos.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
      });
    }
  }

  Future<Position> _getCurrentPositionOrThrow() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('يرجى تفعيل خدمة الموقع (GPS) للمتابعة');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw Exception('تم رفض إذن الموقع. يرجى السماح بالموقع للمتابعة');
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception(
          'إذن الموقع مرفوض نهائياً. افتح إعدادات الهاتف وفعّل إذن الموقع للتطبيق');
    }
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  // no map picker

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'الاسم مطلوب');
      return;
    }
    if (phone.isEmpty || phone.length < 7) {
      setState(() => error = 'رقم الهاتف مطلوب');
      return;
    }
    if (lat == null || lng == null) {
      setState(() => error = 'حدد موقعك أولاً');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('فشل التحقق من الحساب');
      final String? idTokenNullable = await user.getIdToken(true);
      if (idTokenNullable == null || idTokenNullable.isEmpty) {
        throw Exception('تعذر الحصول على رمز الدخول، حاول مجدداً');
      }
      final String idToken = idTokenNullable;

      final api = ApiClient(baseUrl: baseUrl);
      final c = await api.firebaseRegisterCustomer(
        idToken: idToken,
        name: name,
        phone: phone,
        lat: lat!,
        lng: lng!,
        address: address,
      );

      await widget.prefs.setInt('customerId', c['id'] as int);
      await widget.prefs.setString('customerName', c['name'] as String);
      await widget.prefs
          .setString('customerPhone', (c['phone'] ?? '') as String);
      await widget.prefs
          .setDouble('defaultLat', (c['defaultLat'] as num).toDouble());
      await widget.prefs
          .setDouble('defaultLng', (c['defaultLng'] as num).toDouble());
      await widget.prefs
          .setString('defaultAddress', (c['defaultAddress'] ?? '') as String);

      widget.state.setCustomer(
        id: c['id'] as int,
        name: c['name'] as String,
        phone: (c['phone'] ?? '') as String,
        lat: (c['defaultLat'] as num).toDouble(),
        lng: (c['defaultLng'] as num).toDouble(),
        address: c['defaultAddress'] as String?,
      );

      // Init FCM token registration and topic.
      try {
        await PushService(api: api, platformTag: 'android')
            .initForCustomer(customerId: c['id'] as int);
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(HomeScreen.route);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: BrandTitle(state: widget.state, suffix: 'إكمال المعلومات'),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF1A1A1A),
        ),
      ),
      body: Column(
        children: [
          Container(
            height: 4,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [primary, theme.colorScheme.secondary],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: primary, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'قبل البدء، اكتب اسمك ورقم هاتفك. سيتم تحديد موقعك تلقائياً عبر GPS.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF424242),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _name,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      labelText: 'اسمك',
                      labelStyle: theme.textTheme.bodyMedium,
                      prefixIcon: Icon(Icons.person_outline_rounded, color: primary),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف',
                      labelStyle: theme.textTheme.bodyMedium,
                      prefixIcon: Icon(Icons.phone_outlined, color: primary),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : _initGps,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(color: primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.my_location_rounded),
                      label: Text(
                        lat == null
                            ? 'تحديد موقعي تلقائياً (GPS)'
                            : 'إعادة تحديد الموقع (GPS)',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                  if (lat != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'تم اختيار الموقع: ${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF616161),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    onChanged: (v) => address = v.trim(),
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      labelText: 'عنوان اختياري (اسم الحي/الشارع)',
                      labelStyle: theme.textTheme.bodyMedium,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (error != null) const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: loading ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                        shadowColor: primary.withOpacity(0.35),
                      ),
                      child: loading
                          ? SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'متابعة',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
