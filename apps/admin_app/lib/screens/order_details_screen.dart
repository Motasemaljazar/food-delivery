import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/api.dart';
import '../models/app_state.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.api, required this.state, required this.orderId});
  final ApiClient api;
  final AppState state;
  final int orderId;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? order;

  int _stars = 5;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final o = await widget.api.getOrder(widget.orderId);
      order = o;
      // Store ETA in cache for list screen
      if (o['expectedDeliveryAtUtc'] != null) {
        widget.state.upsertOrderEta({
          'orderId': widget.orderId,
          'expectedDeliveryAtUtc': o['expectedDeliveryAtUtc'],
          'prepEtaMinutes': o['prepEtaMinutes'],
          'deliveryEtaMinutes': o['deliveryEtaMinutes'],
          'lastEtaUpdatedAtUtc': o['lastEtaUpdatedAtUtc'],
        });
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() { loading = false; });
    }
  }

  String statusName(int s) {
    const list = ['جديد','تم التأكيد','قيد التجهيز','جاهز للاستلام','مع السائق','تم التسليم','ملغي'];
    return (s >= 0 && s < list.length) ? list[s] : '$s';
  }

  String _humanOptions(String? snapshot) {
    final s = (snapshot ?? '').trim();
    if (s.isEmpty) return '';
    try {
      final m = jsonDecode(s);
      if (m is Map) {
        final parts = <String>[];
        final vn = m['variantName']?.toString();
        if (vn != null && vn.trim().isNotEmpty) parts.add(vn);
        final addons = m['addons'];
        if (addons is List && addons.isNotEmpty) {
          final names = addons.map((a) => (a is Map) ? a['name']?.toString() : null).where((x) => x != null && x.trim().isNotEmpty).cast<String>().toList();
          if (names.isNotEmpty) parts.add('إضافات: ${names.join('، ')}');
        }
        final note = m['note']?.toString();
        if (note != null && note.trim().isNotEmpty) parts.add('ملاحظة: $note');
        return parts.join(' • ');
      }
    } catch (_) {}
    return s;
  }

  Widget _etaCard(Map<String, dynamic> o) {
    final prep = (o['prepEtaMinutes'] is num) ? (o['prepEtaMinutes'] as num).toInt() : null;
    final del = (o['deliveryEtaMinutes'] is num) ? (o['deliveryEtaMinutes'] as num).toInt() : null;
    final expected = o['expectedDeliveryAtUtc']?.toString();

    if ((prep == null || prep == 0) && (del == null || del == 0) && (expected == null || expected.isEmpty)) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.timer_outlined),
              SizedBox(width: 10),
              Expanded(child: Text('لم يتم تحديد الوقت المتوقع بعد. سيظهر هنا عند تحديده من الإدارة.')),
            ],
          ),
        ),
      );
    }

    DateTime? expectedDt;
    int? remaining;
    if (expected != null) {
      try {
        expectedDt = DateTime.parse(expected).toLocal();
        remaining = expectedDt.difference(DateTime.now()).inMinutes;
      } catch (_) {}
    }

    final total = (prep ?? 0) + (del ?? 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.access_time),
                SizedBox(width: 10),
                Text('الوقت المتوقع لوصول الطلب', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            if (total > 0)
              Text('التجهيز: ${prep ?? 0} د  •  التوصيل: ${del ?? 0} د  •  المجموع: $total د'),
            if (expectedDt != null) ...[
              const SizedBox(height: 6),
              Text('موعد الوصول التقريبي: ${expectedDt.hour.toString().padLeft(2,'0')}:${expectedDt.minute.toString().padLeft(2,'0')}'),
            ],
            if (remaining != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (total <= 0 || remaining <= 0) ? null : (1 - (remaining / total)).clamp(0.0, 1.0),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(remaining <= 0 ? 'قيد التحديث' : '$remainingد'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _showRatingDialog(int orderId) async {
    _stars = 5;
    _commentCtrl.text = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('قيّم السائق', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final idx = i + 1;
                      return IconButton(
                        onPressed: () => setLocal(() => _stars = idx),
                        icon: Icon(idx <= _stars ? Icons.star : Icons.star_border, size: 32),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'تعليق (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final navigator = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(ctx);
                      try {
                        await widget.api.rateDriver(
                          orderId: orderId,
                          customerId: widget.state.customerId!,
                          stars: _stars,
                          comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
                        );
                        if (!mounted) return;
                        navigator.pop();
                        messenger.showSnackBar(const SnackBar(content: Text('تم حفظ التقييم ✅')));
                        await _load();
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(SnackBar(content: Text('فشل حفظ التقييم: $e')));
                        }
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('إرسال التقييم'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تفاصيل الطلب #${widget.orderId}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (error != null)
              ? Center(child: Text(error!))
              : _body(),
    );
  }

  Widget _body() {
    final o = order ?? <String, dynamic>{};
    final items = (o['items'] is List) ? (o['items'] as List) : const [];
    final history = (o['history'] is List) ? (o['history'] as List) : const [];

    final status = (o['currentStatus'] ?? 0) as int;
    final rating = o['rating'];
    final canRate = status == 5 && widget.state.customerId != null && (o['driverId'] != null) && (rating == null);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text('الحالة: ${statusName((o['currentStatus'] ?? 0) as int)}'),
            subtitle: Text('الإجمالي: ${(o['total'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}'),
          ),
        ),
        _etaCard(o),
        const SizedBox(height: 6),
        if ((o['deliveryAddress'] ?? '').toString().trim().isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('موقع التوصيل'),
              subtitle: Text(o['deliveryAddress'].toString()),
            ),
          ),

        const SizedBox(height: 10),
        const Text('الأصناف', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ...items.map((it) {
          final m = Map<String, dynamic>.from(it as Map);
          final qty = (m['quantity'] as num?)?.toInt() ?? 1;
          final name = (m['productNameSnapshot'] ?? '').toString();
          final price = (m['unitPriceSnapshot'] as num?)?.toDouble() ?? 0;
          return Card(
            child: ListTile(
              title: Text(name),
              subtitle: _humanOptions(m['optionsSnapshot']?.toString()).trim().isEmpty ? null : Text(_humanOptions(m['optionsSnapshot']?.toString())),
              trailing: Text('x$qty  •  ${(price * qty).toStringAsFixed(2)}'),
            ),
          );
        }),

        const SizedBox(height: 10),
        const Text('سجل الحالة', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (history.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('لا يوجد سجل بعد')))
        else
          ...history.map((h) {
            final m = Map<String, dynamic>.from(h as Map);
            final st = (m['status'] ?? 0) as int;
            final when = m['changedAtUtc']?.toString();
            String timeText = '';
            if (when != null) {
              try {
                final dt = DateTime.parse(when).toLocal();
                timeText = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
              } catch (_) {}
            }
            final comment = (m['comment'] ?? '').toString();
            return Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(statusName(st)),
                subtitle: comment.trim().isEmpty ? null : Text(comment),
                trailing: Text(timeText),
              ),
            );
          }),

        const SizedBox(height: 12),
        if (canRate)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تم تسليم الطلب ✅', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('ساعدنا بتقييم السائق لتحسين الخدمة.'),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _showRatingDialog(widget.orderId),
                    icon: const Icon(Icons.star_rate),
                    label: const Text('تقييم السائق'),
                  ),
                ],
              ),
            ),
          ),
        if (rating != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.star),
              title: Text('تقييمك: ${(rating['stars'] ?? 0).toString()} / 5'),
              subtitle: (rating['comment'] ?? '').toString().trim().isEmpty ? null : Text(rating['comment'].toString()),
            ),
          ),
      ],
    );
  }
}
