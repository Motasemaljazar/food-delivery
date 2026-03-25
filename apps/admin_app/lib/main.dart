import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_config.dart';
import 'screens/admin_login_screen.dart';
import 'screens/admin_main_shell.dart';
import 'services/admin_auth_storage.dart';
import 'theme/admin_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar', null);
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ادمن توب شيف',
      locale: const Locale('ar'),
      theme: AdminTheme.lightTheme,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox(),
        );
      },
      home: const AdminHomeResolver(),
    );
  }
}

/// يعرض شاشة الدخول إن لم يكن هناك مفتاح محفوظ، وإلا يعرض الواجهة الرئيسية الأصلية.
class AdminHomeResolver extends StatefulWidget {
  const AdminHomeResolver({super.key});

  @override
  State<AdminHomeResolver> createState() => _AdminHomeResolverState();
}

class _AdminHomeResolverState extends State<AdminHomeResolver> {
  final AdminAuthStorage _storage = AdminAuthStorage();
  bool _checked = false;
  String? _savedKey;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final key = await _storage.getAdminKey();
    if (mounted) setState(() {
      _savedKey = key;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_savedKey != null && _savedKey!.isNotEmpty) {
      return AdminMainShell(baseUrl: kBackendBaseUrl, adminKey: _savedKey!);
    }
    return const AdminLoginScreen();
  }
}
