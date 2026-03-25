import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import '../widgets/brand_title.dart';
import '../services/push.dart';
import 'complete_profile_screen.dart';
import 'home_screen.dart';
import 'blocked_screen.dart';

enum AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  static const route = '/auth';
  const AuthScreen({super.key, required this.prefs, required this.state});

  final SharedPreferences prefs;
  final AppState state;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode mode = AuthMode.login;
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;
  bool obscure = true;
  String? error;

  String get baseUrl => kBackendBaseUrl;

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> _afterAuth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل تسجيل الدخول، حاول مجدداً')));
      return;
    }
    // التحقق من البريد مطلوب فقط لتسجيل البريد/كلمة المرور وليس لتسجيل الدخول عبر Google
    final isGoogleUser = user.providerData.any((p) => p.providerId == 'google.com');
    if (!isGoogleUser && !user.emailVerified) {
      try { await FirebaseAuth.instance.signOut(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        error = 'يجب تفعيل الحساب أولاً. راجع بريدك الإلكتروني وافتح رابط التفعيل ثم سجّل الدخول مرة أخرى.';
      });
      return;
    }
    final String? idTokenNullable = await user.getIdToken();
    if (idTokenNullable == null || idTokenNullable.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر الحصول على رمز الدخول، حاول مجدداً')));
      return;
    }
    final String idToken = idTokenNullable;

    final api = ApiClient(baseUrl: baseUrl);
    Map<String, dynamic> session;
    try {
      session = await api.firebaseCustomerSession(idToken: idToken);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'تعذر الاتصال بالسيرفر أو التحقق من الحساب.\nتفاصيل: $e';
      });
      return;
    }
    if (!mounted) return;

    // حساب موقوف من الإدارة — الانتقال لشاشة الحظر
    if (session.containsKey('error') && session['error'] == 'customer_blocked') {
      try { await FirebaseAuth.instance.signOut(); } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BlockedScreen(prefs: widget.prefs, state: widget.state),
        ),
      );
      return;
    }

    if (session['requiresProfile'] == true) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CompleteProfileScreen(
            prefs: widget.prefs,
            state: widget.state,
            email: session['email'] as String?,
            suggestedName: session['name'] as String?,
          ),
        ),
      );
      return;
    }

    final cid = session['id'] as int;
    await _persistCustomer(session);
    try {
      await PushService(api: api, platformTag: 'android').initForCustomer(customerId: cid);
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(HomeScreen.route);
  }

  Future<void> _persistCustomer(Map<String, dynamic> c) async {
    await widget.prefs.setInt('customerId', c['id'] as int);
    await widget.prefs.setString('customerName', (c['name'] ?? '') as String);
    await widget.prefs.setString('customerPhone', (c['phone'] ?? '') as String);
    await widget.prefs.setDouble('defaultLat', (c['defaultLat'] as num).toDouble());
    await widget.prefs.setDouble('defaultLng', (c['defaultLng'] as num).toDouble());
    await widget.prefs.setString('defaultAddress', (c['defaultAddress'] ?? '') as String);
    widget.state.setCustomer(
      id: c['id'] as int,
      name: (c['name'] ?? '') as String,
      phone: (c['phone'] ?? '') as String,
      lat: (c['defaultLat'] as num).toDouble(),
      lng: (c['defaultLng'] as num).toDouble(),
      address: c['defaultAddress'] as String?,
    );
  }

  Future<void> _loginOrRegister() async {
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => error = 'أدخل بريد إلكتروني صحيح');
      return;
    }
    if (pass.length < 6) {
      setState(() => error = 'كلمة المرور يجب أن لا تقل عن 6 أحرف');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (mode == AuthMode.login) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
        await _afterAuth();
      } else {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
        if (cred.user != null) {
          await cred.user!.sendEmailVerification();
          if (!mounted) return;
          setState(() {
            error = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إرسال رسالة التفعيل إلى بريدك الإلكتروني. راجع صندوق الوارد (أو البريد المزعج) وافتح رابط التفعيل، ثم سجّل الدخول.'),
              duration: Duration(seconds: 6),
            ),
          );
          try { await FirebaseAuth.instance.signOut(); } catch (_) {}
          return;
        }
        await _afterAuth();
      }
    } on FirebaseAuthException catch (e) {
      setState(() => error = _humanError(e.code));
    } catch (_) {
      setState(() => error = 'تعذر إكمال العملية، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final uri = Uri.parse(kPrivacyPolicyUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح رابط سياسة الخصوصية')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح الرابط')));
      }
    }
  }

  Future<void> _openTermsOfUse(BuildContext context) async {
    final uri = Uri.parse(kTermsOfUseUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح رابط شروط الاستخدام')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح الرابط')));
      }
    }
  }

  String _humanError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'الحساب غير موجود';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة';
      case 'email-already-in-use':
        return 'البريد مستخدم مسبقاً';
      case 'invalid-email':
        return 'البريد غير صالح';
      case 'network-request-failed':
        return 'تحقق من اتصال الإنترنت';
      default:
        return 'حدث خطأ، حاول مرة أخرى';
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (kIsWeb) {
        // GoogleSignIn plugin is not reliable on Web without extra clientId config.
        // Firebase Web supports popup flow natively.
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        final googleSignIn = GoogleSignIn(
          serverClientId: '797032893766-7meb7vaeoml1epqoj95pnfrpsmj9d8le.apps.googleusercontent.com',
        );
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          if (mounted) setState(() => loading = false);
          return;
        }
        final googleAuth = await googleUser.authentication;
        final idToken = googleAuth.idToken;
        final accessToken = googleAuth.accessToken;
        if (idToken == null && accessToken == null) {
          if (mounted) setState(() => error = 'تعذر الحصول على بيانات الدخول من Google');
          return;
        }
        final credential = GoogleAuthProvider.credential(
          accessToken: accessToken,
          idToken: idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
      await _afterAuth();
    } on FirebaseAuthException catch (e) {
      setState(() => error = _humanError(e.code));
    } catch (e, st) {
      if (kDebugMode) debugPrint('Google sign-in error: $e\n$st');
      setState(() => error = 'تعذر تسجيل الدخول عبر Google. تأكد من الاتصال بالإنترنت وإعدادات التطبيق.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.secondary;
    final isLogin = mode == AuthMode.login;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: BrandTitle(state: widget.state, suffix: 'تسجيل الدخول'),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF1A1A1A),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // شريط علوي أحمر-أصفر
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [primary, secondary],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final logo = (widget.state.logoUrl ?? '').trim();
                      if (logo.isNotEmpty) {
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: primary.withOpacity(0.15),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.network(
                              logo,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(width: 100, height: 100),
                            ),
                          ),
                        );
                      }
                      return const SizedBox(width: 100, height: 100);
                    }),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'مرحباً بعودتك في ${widget.state.restaurantName.trim().isEmpty ? 'توب شيف' : widget.state.restaurantName.trim()}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        isLogin ? 'سجّل الدخول للمتابعة' : 'أنشئ حساباً جديداً للمتابعة',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF616161),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // تبديل تسجيل الدخول / إنشاء حساب
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF0F0F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ModeChip(
                              text: 'تسجيل الدخول',
                              active: isLogin,
                              onTap: () => setState(() => mode = AuthMode.login),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ModeChip(
                              text: 'إنشاء حساب',
                              active: !isLogin,
                              onTap: () => setState(() => mode = AuthMode.register),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    _InputCard(
                      child: TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: 'البريد الإلكتروني',
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(color: const Color(0xFF9E9E9E)),
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.email_outlined, color: primary, size: 22),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _InputCard(
                      child: TextField(
                        controller: passCtrl,
                        obscureText: obscure,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: 'كلمة المرور',
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(color: const Color(0xFF9E9E9E)),
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.lock_outline, color: primary, size: 22),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: primary,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.colorScheme.error.withOpacity(0.3)),
                        ),
                        child: Text(
                          error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (error != null) const SizedBox(height: 14),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: loading ? null : _loginOrRegister,
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
                                isLogin ? 'تسجيل الدخول' : 'إنشاء حساب',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),

                    if (!isLogin) ...[
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF616161),
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(
                                  text: 'بالتسجيل في التطبيق، أنت توافق على '),
                              TextSpan(
                                text: 'سياسة الخصوصية',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: primary,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  decorationColor: primary,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _openPrivacyPolicy(context),
                              ),
                              const TextSpan(text: ' و'),
                              TextSpan(
                                text: 'شروط الاستخدام',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: primary,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  decorationColor: primary,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => _openTermsOfUse(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    if (isLogin) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: loading
                            ? null
                            : () async {
                                final email = emailCtrl.text.trim();
                                if (email.isEmpty) {
                                  setState(() => error = 'اكتب بريدك أولاً ثم اضغط نسيت كلمة المرور');
                                  return;
                                }
                                try {
                                  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('تم إرسال رابط استعادة كلمة المرور')),
                                  );
                                } catch (_) {
                                  setState(() => error = 'تعذر إرسال رابط الاستعادة');
                                }
                              },
                        child: Text(
                          'نسيت كلمة المرور؟',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade400, thickness: 1)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'أو',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade400, thickness: 1)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: loading ? null : _googleSignIn,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: BorderSide(color: Colors.grey.shade400),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                        label: Text(
                          'الاتصال بـ Google',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  const _ModeChip({required this.text, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [primary, theme.colorScheme.secondary],
                  )
                : null,
            color: active ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : const Color(0xFF424242),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  final Widget child;
  const _InputCard({required this.child});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
