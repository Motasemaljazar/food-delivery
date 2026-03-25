import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';
import '../services/admin_api.dart';
import '../services/admin_auth_storage.dart';
import 'admin_main_shell.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _keyController = TextEditingController();
  final _storage = AdminAuthStorage();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _error = 'أدخل مفتاح الإدارة';
        _loading = false;
      });
      return;
    }
    try {
      final api = AdminApiService(baseUrl: kBackendBaseUrl, adminKey: key);
      final ok = await api.checkKey();
      if (!ok || !mounted) {
        setState(() {
          _loading = false;
          _error = 'مفتاح غير صحيح أو الخادم غير متاح';
        });
        return;
      }
      await _storage.setAdminKey(key);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AdminMainShell(baseUrl: kBackendBaseUrl, adminKey: key)),
      );
    } on AdminApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.statusCode == 401 ? 'مفتاح الإدارة غير صحيح' : e.body;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'تحقق من الاتصال بالخادم';
      });
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.admin_panel_settings, size: 72, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 24),
                    Text(
                      'ادمن توب شيف',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أدخل مفتاح الإدارة للدخول',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _keyController,
                      decoration: const InputDecoration(
                        labelText: 'مفتاح الإدارة (X-ADMIN-KEY)',
                        border: OutlineInputBorder(),
                        hintText: 'الصق المفتاح من إعدادات الخادم',
                      ),
                      obscureText: true,
                      autofillHints: const [],
                      onFieldSubmitted: (_) => _login(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('دخول'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
