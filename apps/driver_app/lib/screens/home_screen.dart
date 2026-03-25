import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../services/api.dart';
import '../services/realtime.dart';
import '../models/brand_state.dart';
import '../theme/driver_theme.dart';
import 'driver_order_detail_screen.dart';

/// Small wrapper that wires SharedPreferences -> API + token.
class DriverHome extends StatelessWidget {
  const DriverHome({super.key, required this.prefs, required this.brand});
  final SharedPreferences prefs;
  final BrandState brand;

  @override
  Widget build(BuildContext context) {
    final baseUrl = kBackendBaseUrl;
    final token = prefs.getString('driverToken') ?? '';
    final rn = (prefs.getString('restaurantName') ?? '').trim();
    return HomeScreen(api: DriverApi(baseUrl: baseUrl), token: token, restaurantName: rn, brand: brand);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.token, this.restaurantName = '', required this.brand});
  final DriverApi api;
  final String token;
  final String restaurantName;
  final BrandState brand;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;

  String _restaurantName = '';

  RealtimeClient? _rt;

  double? _restaurantLat;
  double? _restaurantLng;
  List<Map<String, dynamic>> _orders = [];

  int _todayDelivered = 0;
  double _todayCash = 0;
  bool _statsLoading = false;
  /// عدد الطلبات الجديدة التي وصلت ولم يُفتح تبويب الطلبات بعد (لإظهار الدائرة بجانب أيقونة الطلبات)
  int _newOrdersCount = 0;

  late TabController _tabController;
  Timer? _timer;

  static const int _stNew = 0;
  static const int _stConfirmed = 1;
  static const int _stPreparing = 2;
  static const int _stReadyForPickup = 3;
  static const int _stWithDriver = 4;
  static const int _stDelivered = 5;
  static const int _stCancelled = 6;
  static const int _stAccepted = 7;

  String _statusLabel(int s) {
    switch (s) {
      case _stNew: return 'جديد';
      case _stConfirmed: return 'تم التأكيد';
      case _stPreparing: return 'قيد التحضير';
      case _stReadyForPickup: return 'جاهز للاستلام';
      case _stAccepted: return 'تم القبول';
      case _stWithDriver: return 'مع السائق';
      case _stDelivered: return 'تم التسليم';
      case _stCancelled: return 'ملغى';
      default: return '$s';
    }
  }

  @override
  void initState() {
    super.initState();
    _restaurantName = widget.restaurantName;

    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final rn = (prefs.getString('restaurantName') ?? '').trim();
        if (rn.isNotEmpty && mounted) setState(() => _restaurantName = rn);
      } catch (_) {}
    }();

    try {
      _rt = RealtimeClient(baseUrl: widget.api.baseUrl);
      _rt!.connectDriver(
        token: widget.token,
        onSettingsUpdated: (s) async {
          final rn = (s['restaurantName'] ?? '').toString();
          if (rn.trim().isNotEmpty) {
            setState(() => _restaurantName = rn);
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('restaurantName', rn);
            } catch (_) {}
          }
        },
        onOrderAssigned: (p) async {
          try { SystemSound.play(SystemSoundType.alert); } catch (_) {}
          if (!mounted) return;
          setState(() => _newOrdersCount = _newOrdersCount + 1);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وصلتك مهمة جديدة')));
          await _loadActiveOrders(silent: true);
          await _loadTodayStats(silent: true);
        },
        onOrderUpdated: (_) async {
          await _loadActiveOrders(silent: true);
          await _loadTodayStats(silent: true);
        },
      );
    } catch (_) {}

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) setState(() => _newOrdersCount = 0);
    });
    _loadActiveOrders();
    _loadTodayStats();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _loadActiveOrders(silent: true));
    Timer.periodic(const Duration(seconds: 25), (_) => _loadTodayStats(silent: true));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    _rt?.disconnect();
    super.dispose();
  }

  Future<void> _loadTodayStats({bool silent = false}) async {
    if (_statsLoading) return;
    setState(() => _statsLoading = true);
    try {
      final res = await widget.api.todayStats(widget.token);
      final dc = (res['deliveredCount'] is num) ? (res['deliveredCount'] as num).toInt() : 0;
      final cash = (res['cashCollected'] is num) ? (res['cashCollected'] as num).toDouble() : 0.0;
      if (mounted) setState(() { _todayDelivered = dc; _todayCash = cash; });
    } catch (_) {}
    finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadActiveOrders({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.api.activeOrders(widget.token);
      final orders = (data['orders'] as List?) ?? const [];
      setState(() {
        _restaurantLat = (data['restaurantLat'] as num?)?.toDouble();
        _restaurantLng = (data['restaurantLng'] as num?)?.toDouble();
        _orders = orders.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!silent) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── بطاقة طلب مضغوطة (تفتح صفحة التفاصيل عند الضغط) ──
  Widget _orderCard(BuildContext context, int i) {
    final o = _orders[i];
    final id = o['id']?.toString() ?? '';
    final statusCode = (o['currentStatus'] as num?)?.toInt() ?? int.tryParse((o['currentStatus'] ?? '').toString()) ?? -1;
    final status = _statusLabel(statusCode);
    final name = (o['customerName'] ?? '').toString();
    final total = (o['total'] ?? '').toString();
    final cs = Theme.of(context).colorScheme;
    final orderId = o['id'] is num ? (o['id'] as num).toInt() : (i + 1);

    return InkWell(
      key: ValueKey('order_$orderId'),
      onTap: () async {
        final refreshed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => DriverOrderDetailScreen(
              order: o,
              api: widget.api,
              token: widget.token,
              restaurantLat: _restaurantLat,
              restaurantLng: _restaurantLng,
            ),
          ),
        );
        if (mounted) {
          _loadActiveOrders(silent: true);
          if (refreshed == true) _loadTodayStats(silent: true);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: DriverTheme.primaryRed.withOpacity(0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DriverTheme.primaryRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long, color: DriverTheme.primaryRed, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('طلب #$id', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(name, style: GoogleFonts.cairo(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('$total ل.س · $status', style: GoogleFonts.cairo(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: DriverTheme.primaryRed.withOpacity(0.2), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DriverTheme.primaryRed.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.insights_rounded, color: DriverTheme.primaryRed, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'إحصائيات اليوم',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _statsRow('الطلبات المُسلّمة', '$_todayDelivered'),
              const SizedBox(height: 12),
              _statsRow('الطلبات قيد التسليم', '${_orders.where((o) => ((o['currentStatus'] as num?)?.toInt() ?? -1) == _stWithDriver).length}'),
              const SizedBox(height: 12),
              _statsRow('المبلغ المُحصّل (ل.س)', _todayCash.toStringAsFixed(0)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _statsLoading ? null : () => _loadTodayStats(),
                  icon: _statsLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded),
                  label: Text(_statsLoading ? 'جاري التحديث...' : 'تحديث الإحصائيات'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DriverTheme.primaryRed,
                    side: const BorderSide(color: DriverTheme.primaryRed),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.cairo(fontSize: 15)),
        Text(value, style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 16)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: Align(
            alignment: Alignment.centerRight,
            child: Text(
              _restaurantName.isNotEmpty ? '$_restaurantName — مهامي' : 'مهامي الحالية',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(icon: const Icon(Icons.insights_outlined), text: 'إحصائيات اليوم'),
              Tab(
                icon: _newOrdersCount > 0
                    ? Badge(
                        label: Text('$_newOrdersCount'),
                        backgroundColor: DriverTheme.primaryRed,
                        child: const Icon(Icons.list_alt),
                      )
                    : const Icon(Icons.list_alt),
                text: 'الطلبات',
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => widget.brand.toggleTheme(),
              icon: Icon(widget.brand.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              tooltip: 'الوضع الليلي',
            ),
            IconButton(onPressed: () { _loadActiveOrders(); _loadTodayStats(); }, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: DriverTheme.primaryRed))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: DriverTheme.primaryRed.withOpacity(0.8)),
                          const SizedBox(height: 16),
                          Text('حدث خطأ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 18)),
                          const SizedBox(height: 8),
                          Text('$_error', textAlign: TextAlign.center, style: GoogleFonts.cairo(fontSize: 14)),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _loadActiveOrders(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      KeyedSubtree(key: const ValueKey('tab_stats'), child: _buildStatsTab()),
                      KeyedSubtree(
                        key: const ValueKey('tab_orders'),
                        child: _orders.isEmpty
                          ? Builder(
                              builder: (context) {
                                final cs = Theme.of(context).colorScheme;
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.inbox_rounded, size: 72, color: cs.onSurfaceVariant),
                                      const SizedBox(height: 16),
                                      Text(
                                        'لا توجد طلبات نشطة',
                                        style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'ستظهر الطلبات هنا عند تعيينها لك',
                                        style: GoogleFonts.cairo(fontSize: 14, color: cs.onSurfaceVariant.withOpacity(0.85)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(top: 12, bottom: 24),
                              itemCount: _orders.length,
                              itemBuilder: (context, i) => _orderCard(context, i),
                            ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
