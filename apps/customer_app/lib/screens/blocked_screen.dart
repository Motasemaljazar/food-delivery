import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_state.dart';
import 'auth_screen.dart';

/// شاشة الحظر - تظهر عندما يتم إيقاف حساب الزبون
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({
    super.key,
    required this.prefs,
    required this.state,
  });

  final SharedPreferences prefs;
  final AppState state;

  static const route = '/blocked';

  Future<void> _handleLogout(BuildContext context) async {
    try {
      // تسجيل الخروج من Firebase
      await FirebaseAuth.instance.signOut();
      
      // حذف جميع البيانات المحلية
      await prefs.remove('customerId');
      await prefs.remove('customerName');
      await prefs.remove('customerPhone');
      await prefs.remove('defaultLat');
      await prefs.remove('defaultLng');
      await prefs.remove('defaultAddress');
      
      // إعادة تعيين حالة التطبيق
      state.clearCustomer();
      
      if (!context.mounted) return;
      
      // الانتقال إلى شاشة تسجيل الدخول
      Navigator.of(context).pushNamedAndRemoveUntil(
        AuthScreen.route,
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء تسجيل الخروج')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.errorContainer.withOpacity(0.1),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // أيقونة الحظر
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.error.withOpacity(0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.block_rounded,
                    size: 80,
                    color: colorScheme.error,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // العنوان
                Text(
                  'تم إيقاف حسابك',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // الرسالة
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: colorScheme.error.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 48,
                          color: colorScheme.error.withOpacity(0.7),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'تم إيقاف حسابك من قبل الإدارة',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'للاستفسار عن سبب الإيقاف أو لطلب إعادة تفعيل الحساب، يرجى التواصل مع الدعم الفني',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey.shade700,
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // معلومات التواصل
                if (state.supportPhone.isNotEmpty || state.supportWhatsApp.isNotEmpty)
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Text(
                            'للتواصل مع الدعم:',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (state.supportPhone.isNotEmpty)
                            _ContactButton(
                              icon: Icons.phone_rounded,
                              label: 'اتصال',
                              value: state.supportPhone,
                              url: 'tel:${state.supportPhone}',
                              color: colorScheme.primary,
                            ),
                          if (state.supportPhone.isNotEmpty && state.supportWhatsApp.isNotEmpty)
                            const SizedBox(height: 12),
                          if (state.supportWhatsApp.isNotEmpty)
                            _ContactButton(
                              icon: Icons.message_rounded,
                              label: 'واتساب',
                              value: state.supportWhatsApp,
                              url: 'https://wa.me/${state.supportWhatsApp.replaceAll(RegExp(r'[^\d+]'), '')}',
                              color: const Color(0xFF25D366),
                            ),
                        ],
                      ),
                    ),
                  ),
                
                const SizedBox(height: 32),
                
                // زر تسجيل الخروج
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _handleLogout(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text(
                      'تسجيل الخروج',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.url,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String url;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تعذر فتح الرابط')),
            );
          }
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 20,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
