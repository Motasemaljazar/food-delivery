import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_api.dart';

String _reportNum(dynamic v) {
  if (v == null) return '—';
  if (v is num) return v is double ? v.toStringAsFixed(2) : v.toString();
  return v.toString();
}

String _reportInt(dynamic v) {
  if (v == null) return '—';
  if (v is int) return v.toString();
  if (v is num) return v.toInt().toString();
  return v.toString();
}

/// صفحة التقارير الأصلية — اليوم / الأسبوع / الشهر مع الجداول والبطاقات.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _weekly;
  Map<String, dynamic>? _monthly;
  List<dynamic>? _productsDaily;
  List<dynamic>? _driversDaily;
  Map<String, dynamic>? _top;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getReportsSummary(),
        widget.api.getReportsWeeklySummary(),
        widget.api.getReportsMonthlySummary(),
        widget.api.getReportsProductsDaily(),
        widget.api.getReportsDriversDaily(),
        widget.api.getReportsTop(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _weekly = results[1] as Map<String, dynamic>;
        _monthly = results[2] as Map<String, dynamic>;
        _productsDaily = results[3] as List<dynamic>;
        _driversDaily = results[4] as List<dynamic>;
        _top = results[5] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('AdminApiException:', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'اليوم'),
            Tab(text: 'الأسبوع'),
            Tab(text: 'الشهر'),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: TabBarView(
              controller: _tabController,
              children: [
                _TodayPane(
                  summary: _summary!,
                  productsDaily: _productsDaily ?? [],
                  driversDaily: _driversDaily ?? [],
                  top: _top ?? {},
                ),
                _RangePane(data: _weekly ?? {}, title: 'الأسبوع'),
                _RangePane(data: _monthly ?? {}, title: 'الشهر'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayPane extends StatelessWidget {
  const _TodayPane({
    required this.summary,
    required this.productsDaily,
    required this.driversDaily,
    required this.top,
  });

  final Map<String, dynamic> summary;
  final List<dynamic> productsDaily;
  final List<dynamic> driversDaily;
  final Map<String, dynamic> top;

  @override
  Widget build(BuildContext context) {
    final salesToday = summary['salesToday'];
    final ordersCount = summary['ordersCount'];
    final avgPrep = summary['avgPrepEtaMinutes'];
    final topProducts = summary['topProducts'] as List<dynamic>? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('ملخص اليوم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Card(
                title: 'مبيعات اليوم',
                value: salesToday != null ? '${_reportNum(salesToday)} ل.س' : '—',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Card(title: 'عدد الطلبات', value: _reportInt(ordersCount)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Card(
                title: 'متوسط وقت التحضير (د)',
                value: avgPrep != null ? _reportNum(avgPrep) : '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _TableSection(
          title: 'أفضل المنتجات (اليوم)',
          headers: const ['المنتج', 'الكمية'],
          rows: topProducts.map((p) => [p['name']?.toString() ?? '—', _reportInt(p['qty'])]).toList(),
        ),
        const SizedBox(height: 16),
        _TableSection(
          title: 'مبيعات الأصناف اليوم (تم التسليم)',
          headers: const ['المنتج', 'الكمية', 'الإيراد'],
          rows: productsDaily
              .map((r) => [
                    r['name']?.toString() ?? '—',
                    _reportInt(r['qty']),
                    '${_reportNum(r['revenue'])} ل.س',
                  ])
              .toList(),
        ),
        const SizedBox(height: 16),
        _TableSection(
          title: 'تقارير السائقين اليوم (تم التسليم)',
          headers: const ['السائق', 'الطلبات', 'المجموع', 'المسافة (كم)'],
          rows: driversDaily
              .map((r) => [
                    r['driverName']?.toString() ?? '—',
                    _reportInt(r['deliveredCount']),
                    '${_reportNum(r['totalAmount'])} ل.س',
                    _reportNum(r['totalDistanceKm']),
                  ])
              .toList(),
        ),
        const SizedBox(height: 16),
        _TableSection(
          title: 'أفضل السائقين (اليوم)',
          headers: const ['السائق', 'الطلبات', 'المجموع', 'متوسط التوصيل (د)'],
          rows: (top['topDrivers'] as List<dynamic>? ?? [])
              .map((r) => [
                    r['driverName']?.toString() ?? '—',
                    _reportInt(r['deliveredCount']),
                    '${_reportNum(r['totalAmount'])} ل.س',
                    r['avgDeliveryMinutes'] != null ? _reportNum(r['avgDeliveryMinutes']) : '—',
                  ])
              .toList(),
        ),
        const SizedBox(height: 16),
        _TableSection(
          title: 'أفضل الأصناف (اليوم)',
          headers: const ['الصنف', 'الكمية', 'الإيراد'],
          rows: (top['topProducts'] as List<dynamic>? ?? [])
              .map((r) => [
                    r['name']?.toString() ?? '—',
                    _reportInt(r['qty']),
                    '${_reportNum(r['revenue'])} ل.س',
                  ])
              .toList(),
        ),
      ],
    );
  }
}

class _RangePane extends StatelessWidget {
  const _RangePane({required this.data, required this.title});

  final Map<String, dynamic> data;
  final String title;

  @override
  Widget build(BuildContext context) {
    final sales = data['sales'];
    final ordersCount = data['ordersCount'];
    final avgDelivery = data['avgDeliveryEtaMinutes'];
    final daily = data['daily'] as List<dynamic>? ?? [];
    final topProducts = data['topProducts'] as List<dynamic>? ?? [];
    final topDrivers = data['topDrivers'] as List<dynamic>? ?? [];

    final dateFormat = DateFormat.yMd('ar');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('ملخص $title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Card(
                title: 'المبيعات',
                value: sales != null ? '${_reportNum(sales)} ل.س' : '—',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Card(title: 'عدد الطلبات', value: _reportInt(ordersCount)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Card(
                title: 'متوسط التوصيل (د)',
                value: avgDelivery != null ? _reportNum(avgDelivery) : '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _TableSection(
          title: 'تفاصيل الأيام',
          headers: const ['التاريخ', 'الطلبات', 'الإيراد'],
          rows: daily
              .map((r) => [
                    dateFormat.format(DateTime.parse(r['dateUtc'].toString()).toLocal()),
                    _reportInt(r['ordersCount']),
                    '${_reportNum(r['sales'])} ل.س',
                  ])
              .toList(),
        ),
        const SizedBox(height: 16),
        _TableSection(
          title: 'أفضل الأصناف ($title)',
          headers: const ['الصنف', 'الكمية', 'الإيراد'],
          rows: topProducts
              .map((r) => [
                    r['name']?.toString() ?? '—',
                    _reportInt(r['qty']),
                    '${_reportNum(r['revenue'])} ل.س',
                  ])
              .toList(),
        ),
        const SizedBox(height: 16),
        _TableSection(
          title: 'أفضل السائقين ($title)',
          headers: const ['السائق', 'الطلبات', 'المجموع', 'المسافة (كم)', 'متوسط التوصيل (د)'],
          rows: topDrivers
              .map((r) => [
                    r['driverName']?.toString() ?? '—',
                    _reportInt(r['deliveredCount']),
                    '${_reportNum(r['totalAmount'])} ل.س',
                    _reportNum(r['totalDistanceKm']),
                    r['avgDeliveryMinutes'] != null ? _reportNum(r['avgDeliveryMinutes']) : '—',
                  ])
              .toList(),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _TableSection extends StatelessWidget {
  const _TableSection({required this.title, required this.headers, required this.rows});

  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('لا توجد بيانات', style: TextStyle(color: Colors.grey)),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
                  rows: rows
                      .map((row) => DataRow(
                            cells: row.map((cell) => DataCell(Text(cell))).toList(),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
