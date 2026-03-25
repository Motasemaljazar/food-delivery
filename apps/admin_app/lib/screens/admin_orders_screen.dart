import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/admin_api.dart';
import 'admin_order_detail_sheet.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.getOrders();
      if (mounted) setState(() {
        _orders = list;
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
  void initState() {
    super.initState();
    _load();
  }

  static const List<String> _statusNames = [
    'جديد', 'مؤكد', 'جاري التحضير', 'جاهز للاستلام', 'مع السائق', 'تم التوصيل', 'ملغي', 'مقبول',
  ];

  @override
  Widget build(BuildContext context) {
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _orders.isEmpty) {
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemCount: _orders.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return const SizedBox(height: 8);
          final o = _orders[i - 1] as Map<String, dynamic>;
          final id = o['id'] as int? ?? 0;
          final status = o['currentStatus'] as int? ?? 0;
          final total = (o['total'] as num?)?.toDouble() ?? 0;
          final customerName = o['customerName'] as String? ?? '#$id';
          final createdAt = o['createdAtUtc'];
          DateTime? dt;
          if (createdAt != null) {
            try {
              dt = DateTime.parse(createdAt.toString());
            } catch (_) {}
          }
          final timeStr = dt != null ? DateFormat('HH:mm · yyyy/MM/dd').format(dt) : '—';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Row(
                children: [
                  Text('#$id', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(customerName, overflow: TextOverflow.ellipsis)),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Chip(
                      label: Text(_statusNames[status > 7 ? 0 : status], style: const TextStyle(fontSize: 12)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 8),
                    Text('$total ل.س', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        timeStr,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () async {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (ctx) => AdminOrderDetailSheet(orderId: id, api: widget.api, onUpdated: _load),
                );
                if (context.mounted) _load();
              },
            ),
          );
        },
      ),
    );
  }
}
