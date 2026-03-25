import 'package:flutter/material.dart';

import '../services/admin_api.dart';

class AdminOrderDetailSheet extends StatefulWidget {
  const AdminOrderDetailSheet({
    super.key,
    required this.orderId,
    required this.api,
    required this.onUpdated,
  });
  final int orderId;
  final AdminApiService api;
  final VoidCallback onUpdated;

  @override
  State<AdminOrderDetailSheet> createState() => _AdminOrderDetailSheetState();
}

class _AdminOrderDetailSheetState extends State<AdminOrderDetailSheet> {
  Map<String, dynamic>? _order;
  List<dynamic> _drivers = [];
  bool _loading = true;
  String? _error;
  int? _selectedDriverId;
  int? _prepEta;
  int? _deliveryEta;
  final _prepController = TextEditingController();
  final _deliveryController = TextEditingController();
  final _deliveryFeeController = TextEditingController();

  static const List<String> _statusNames = [
    'جديد', 'مؤكد', 'جاري التحضير', 'جاهز للاستلام', 'مع السائق', 'تم التوصيل', 'ملغي', 'مقبول',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prepController.dispose();
    _deliveryController.dispose();
    _deliveryFeeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await widget.api.getOrder(widget.orderId);
      final drivers = await widget.api.getDrivers();
      if (!mounted) return;
      setState(() {
        _order = order;
        _drivers = drivers;
        _loading = false;
        _selectedDriverId = order['driverId'] as int?;
        _prepEta = order['prepEtaMinutes'] as int?;
        _deliveryEta = order['deliveryEtaMinutes'] as int?;
        _prepController.text = _prepEta?.toString() ?? '';
        _deliveryController.text = _deliveryEta?.toString() ?? '';
        final fee = order['deliveryFee'];
        _deliveryFeeController.text = fee != null ? (fee is num ? fee.toString() : fee.toString()) : '';
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('AdminApiException:', '');
        _loading = false;
      });
    }
  }

  Future<void> _assignDriver() async {
    if (_selectedDriverId == (_order?['driverId'] as int?)) return;
    try {
      await widget.api.assignDriver(widget.orderId, _selectedDriverId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعيين السائق')));
        _load();
        widget.onUpdated();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('AdminApiException:', ''))),
      );
    }
  }

  Future<void> _setEta() async {
    final prep = int.tryParse(_prepController.text.trim());
    final del = int.tryParse(_deliveryController.text.trim());
    try {
      await widget.api.setOrderEta(widget.orderId, prep, del);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الوقت المتوقع')));
        _load();
        widget.onUpdated();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('AdminApiException:', ''))),
      );
    }
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text('هل أنت متأكد من إلغاء هذا الطلب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، إلغاء')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.api.cancelOrder(widget.orderId);
      if (mounted) {
        Navigator.pop(context);
        widget.onUpdated();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('AdminApiException:', ''))),
      );
    }
  }

  Future<void> _updateDeliveryFee() async {
    final fee = double.tryParse(_deliveryFeeController.text.trim().replaceFirst(',', '.'));
    if (fee == null) return;
    try {
      await widget.api.updateOrderDeliveryFee(widget.orderId, fee);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث رسوم التوصيل')));
        _load();
        widget.onUpdated();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('AdminApiException:', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _order == null) {
      return DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, __) => const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _order == null) {
      return DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, __) => Padding(
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
    final o = _order!;
    final status = o['currentStatus'] as int? ?? 0;
    final canEdit = status != 6 && status != 7; // not Delivered, not Cancelled

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text('طلب #${o['id']}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Chip(
                  label: Text(_statusNames[status > 7 ? 0 : status]),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('العميل: ${o['customerName'] ?? '—'}', style: const TextStyle(fontSize: 14)),
            if (o['deliveryAddress'] != null && o['deliveryAddress'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('العنوان: ${o['deliveryAddress']}', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              ),
            const SizedBox(height: 12),
            ...((o['items'] as List?) ?? []).map<Widget>((i) {
              final m = i as Map;
              final q = m['quantity'] as int? ?? 0;
              final name = m['productNameSnapshot'] ?? m['productId']?.toString() ?? '—';
              final price = (m['unitPriceSnapshot'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text('$q × ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                    Text('${(price * q).toStringAsFixed(1)} ل.س'),
                  ],
                ),
              );
            }),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المجموع الفرعي:'),
                Text('${(o['subtotal'] as num?)?.toStringAsFixed(1) ?? '0'} ل.س'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('رسوم التوصيل:'),
                Text('${(o['deliveryFee'] as num?)?.toStringAsFixed(1) ?? '0'} ل.س'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('الإجمالي:', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                Text('${(o['total'] as num?)?.toStringAsFixed(1) ?? '0'} ل.س', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (canEdit) ...[
              const SizedBox(height: 16),
              const Text('تعديل رسوم التوصيل:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _deliveryFeeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'رسوم التوصيل',
                        suffixText: 'ل.س',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _updateDeliveryFee, child: const Text('حفظ')),
                ],
              ),
              const SizedBox(height: 16),
              const Text('تعيين السائق:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _selectedDriverId,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('— بدون سائق —')),
                        ..._drivers.map<DropdownMenuItem<int?>>((d) {
                          final m = d as Map;
                          final id = m['id'] as int? ?? 0;
                          final name = m['name'] as String? ?? 'سائق #$id';
                          return DropdownMenuItem(value: id, child: Text(name));
                        }),
                      ],
                      onChanged: (v) => setState(() => _selectedDriverId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _assignDriver, child: const Text('تعيين')),
                ],
              ),
              const SizedBox(height: 12),
              const Text('الوقت المتوقع (دقائق):', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _prepController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'تحضير'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _deliveryController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'توصيل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _setEta, child: const Text('تحديث')),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء الطلب'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: _cancelOrder,
              ),
            ],
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
