import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import 'orders_screen.dart';
import 'cart_screen.dart';
import 'menu_screen.dart';
import 'complaints_screen.dart';
import 'notifications_screen.dart';
import '../services/realtime.dart';

class HomeScreen extends StatefulWidget {
  static const route = '/home';
  const HomeScreen({super.key, required this.prefs, required this.state});
  final SharedPreferences prefs;
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int idx = 0;
  late final ApiClient api;
  late final RealtimeClient rt;

  @override
  void initState() {
    super.initState();
    api = ApiClient(baseUrl: kBackendBaseUrl);
    rt = RealtimeClient(baseUrl: kBackendBaseUrl);
    _connectRealtime();
  }

  Future<void> _connectRealtime() async {
    final id = widget.state.customerId;
    if (id == null) return;
    await rt.connectCustomer(
      customerId: id,
      onNotification: (n) => widget.state.pushNotification(n),
      onOrderStatus: (p) {},
      onOrderEta: (p) { widget.state.upsertOrderEta(p); },
      onComplaintMessage: (p) {},
      onNotificationRefresh: () async {
        try {
          final list = await api.listNotifications(id);
          widget.state.setNotifications(list);
        } catch (_) {}
      },
    );
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _connectRealtime();
  }

  @override
  void dispose() {
    rt.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MenuScreen(api: api, state: widget.state),
      CartScreen(api: api, state: widget.state),
      OrdersScreen(api: api, state: widget.state),
      ComplaintsScreen(api: api, state: widget.state),
    ];

    return AnimatedBuilder(
      animation: widget.state,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          title: Text('أهلاً ${widget.state.customerName ?? ''}'),
          actions: [
            IconButton(
              tooltip: 'الإشعارات',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsScreen(api: api, state: widget.state))),
              icon: Stack(children: [
                const Icon(Icons.notifications),
                if (widget.state.unreadNotifications > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        widget.state.unreadNotifications > 99 ? '99+' : '${widget.state.unreadNotifications}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  )
              ]),
            ),
          ],
        ),
        body: pages[idx],
        bottomNavigationBar: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: (v)=>setState(()=>idx=v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'القائمة'),
            NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'السلة'),
            NavigationDestination(icon: Icon(Icons.receipt_long), label: 'طلباتي'),
            NavigationDestination(icon: Icon(Icons.support_agent), label: 'الدعم'),
          ],
        ),
      ),
    );
  }
}
