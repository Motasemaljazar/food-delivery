import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../services/api.dart';
import '../services/push.dart';
import '../services/foreground_service.dart';
import 'home_screen.dart';
import '../models/brand_state.dart';
import '../theme/driver_theme.dart';

class DriverLogin extends StatefulWidget {
  const DriverLogin({super.key, required this.prefs, required this.brand});
  final SharedPreferences prefs;
  final BrandState brand;

  @override
  State<DriverLogin> createState() => _DriverLoginState();
}

class _DriverLoginState extends State<DriverLogin> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _loading = false;
  String? _err;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final api = DriverApi(baseUrl: kBackendBaseUrl);
      final json = await api.login(phone: _phone.text.trim(), pin: _pin.text.trim());
      await widget.prefs.setString('driverToken', json['token'] as String);
      await widget.prefs.setInt('driverId', json['driver']['id'] as int);
      try {
        final vt = json['driver']['vehicleType'];
        if (vt != null) await widget.prefs.setInt('vehicleType', (vt as num).toInt());
      } catch (_) {}

      try {
        await DriverForegroundService.ensureRunning();
      } catch (_) {}

      try {
        final s = await api.publicSettings();
        try {
          await widget.brand.setConfig(s);
        } catch (_) {}
        if (s['restaurantName'] != null) {
          await widget.prefs.setString('restaurantName', s['restaurantName'].toString());
        }
        if (s['logoUrl'] != null) {
          await widget.prefs.setString('logoUrl', s['logoUrl'].toString());
        }
        if (s['primaryColor'] != null) {
          await widget.prefs.setString('primaryColor', s['primaryColor'].toString());
        }
        if (s['secondaryColor'] != null) {
          await widget.prefs.setString('secondaryColor', s['secondaryColor'].toString());
        }
        if (s['routingProfile'] != null) {
          await widget.prefs.setString('routingProfile', s['routingProfile'].toString());
        }
        if (s['driverSpeedBikeKmH'] != null) {
          await widget.prefs.setDouble(
              'driverSpeedBikeKmH', (s['driverSpeedBikeKmH'] as num).toDouble());
        }
        if (s['driverSpeedCarKmH'] != null) {
          await widget.prefs.setDouble(
              'driverSpeedCarKmH', (s['driverSpeedCarKmH'] as num).toDouble());
        }
      } catch (_) {}

      try {
        await DriverPushService(api: api, platformTag: 'android')
            .initForDriver(driverToken: json['token'] as String);
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => DriverHome(prefs: widget.prefs, brand: widget.brand)),
      );
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rn = widget.prefs.getString('restaurantName') ?? '';
    final title = rn.trim().isEmpty ? 'تطبيق السائق' : '${rn.trim()} — السائق';

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFC41E3A),
              Color(0xFFD32F2F),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Icon(
                Icons.delivery_dining,
                size: 64,
                color: Colors.white.withOpacity(0.95),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'تسجيل الدخول',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _phone,
                                    decoration: InputDecoration(
                                      labelText: 'رقم الهاتف',
                                      prefixIcon: const Icon(Icons.phone_android),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    keyboardType: TextInputType.phone,
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty ? 'مطلوب' : null,
                                  ),
                                  const SizedBox(height: 20),
                                  TextFormField(
                                    controller: _pin,
                                    decoration: InputDecoration(
                                      labelText: 'رمز الدخول',
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    obscureText: true,
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty ? 'مطلوب' : null,
                                  ),
                                  if (_err != null) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: DriverTheme.primaryRed.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: DriverTheme.primaryRed.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        _err!,
                                        style: GoogleFonts.cairo(
                                          fontSize: 13,
                                          color: DriverTheme.primaryRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: DriverTheme.primaryRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'دخول',
                                    style: GoogleFonts.cairo(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
