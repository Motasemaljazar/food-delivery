import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/admin_api.dart';
import '../services/api.dart';
import '../services/push.dart';
import '../widgets/admin_content.dart';
import 'admin_drivers_screen.dart';
import 'admin_live_map_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_native_screen.dart';

class AdminMainShell extends StatefulWidget {
  const AdminMainShell(
      {super.key, required this.baseUrl, required this.adminKey});
  final String baseUrl;
  final String adminKey;

  @override
  State<AdminMainShell> createState() => _AdminMainShellState();
}

class _AdminMainShellState extends State<AdminMainShell> {
  int _index = 0;
  late final AdminApiService _api;

  @override
  void initState() {
    super.initState();
    _api = AdminApiService(baseUrl: widget.baseUrl, adminKey: widget.adminKey);

    // ✅ تفعيل FCM للادمن
    _initFcm();
  }

  Future<void> _initFcm() async {
    try {
      final adminApi = AdminApi(
        baseUrl: widget.baseUrl,
        adminKey: widget.adminKey,
      );
      final pushService =
          AdminPushService(api: adminApi, platformTag: 'android');
      await pushService.initForAdmin();
      debugPrint('✅ [Admin] FCM initialized successfully');
    } catch (e) {
      debugPrint('❌ [Admin] FCM initialization error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          actions: [
            IconButton(
              icon: const Icon(Icons.language),
              tooltip: 'لوحة الويب الكاملة',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('لوحة الويب')),
                      body: adminContent(url: kAdminDashboardUrl),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _index,
            children: [
              AdminOrdersScreen(api: _api),
              AdminDriversScreen(api: _api),
              AdminSettingsNativeScreen(api: _api),
              AdminReportsScreen(api: _api),
              AdminLiveMapScreen(api: _api, selectedTabIndex: _index),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.receipt_long), label: 'الطلبات'),
            NavigationDestination(
                icon: Icon(Icons.delivery_dining), label: 'السائقون'),
            NavigationDestination(
                icon: Icon(Icons.settings), label: 'الإعدادات'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart), label: 'التقارير'),
            NavigationDestination(icon: Icon(Icons.map), label: 'الخريطة'),
          ],
        ),
      ),
    );
  }

  String get _title {
    switch (_index) {
      case 0:
        return 'الطلبات';
      case 1:
        return 'السائقون';
      case 2:
        return 'الإعدادات';
      case 3:
        return 'التقارير';
      case 4:
        return 'الخريطة الحية';
      default:
        return 'ادمن توب شيف';
    }
  }
}
