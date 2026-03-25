import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/api.dart';
import '../models/app_state.dart';
import '../widgets/brand_title.dart';

import '../widgets/support_card.dart';
import 'cart_screen.dart';
import 'complaints_screen.dart';

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

  bool _ratingPrompted = false;

  int _stars = 5;
  final TextEditingController _commentCtrl = TextEditingController();

  bool _cancelSending = false;


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

      // Auto prompt rating once after delivery (skip if user closed with X before)
      if (!_ratingPrompted && mounted && !widget.state.isRatingDismissed(widget.orderId)) {
        final status = (o['currentStatus'] ?? 0) as int;
        final rating = o['orderRating'];
        final driverStars = (rating is Map) ? rating['driverRate'] : null;
        final restaurantStars = (rating is Map) ? rating['restaurantRate'] : null;
        final canRateDriver = status == 5 && widget.state.customerId != null && (o['driverId'] != null) && (driverStars == null);
        final canRateRestaurant = status == 5 && widget.state.customerId != null && (restaurantStars == null);
        if (canRateRestaurant || canRateDriver) {
          _ratingPrompted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showMandatoryRatingDialog(orderId: widget.orderId, rateRestaurant: canRateRestaurant, rateDriver: canRateDriver);
          });
        }
      }
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

  Future<void> _cancelOrder() async {
    final o = order ?? <String, dynamic>{};
    final cid = widget.state.customerId;
    if (cid == null) return;
    if (_cancelSending) return;

    // Server is the source of truth; we also do a quick local check to avoid useless calls.
    try {
      if (o['createdAtUtc'] != null) {
        final created = DateTime.parse(o['createdAtUtc'].toString()).toUtc();
        if (DateTime.now().toUtc().difference(created) > const Duration(minutes: 2)) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('انتهت مدة الإلغاء'),
              content: const Text('لم يعد بإمكانك إلغاء الطلب.\nراجع الإدارة في قسم الدردشة أو اتصال.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComplaintsScreen(api: widget.api, state: widget.state)));
                  },
                  child: const Text('الدردشة'),
                ),
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق')),
              ],
            ),
          );
          return;
        }
      }
    } catch (_) {}

    String reason = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => AlertDialog(
          title: const Text('إلغاء الطلب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('يرجى كتابة سبب الإلغاء (إجباري).'),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'سبب الإلغاء',
                  border: OutlineInputBorder(),
                ),
                maxLength: 160,
                onChanged: (v) => setSt(() => reason = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx2).pop(false), child: const Text('رجوع')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: reason.trim().isEmpty ? null : () => Navigator.of(ctx2).pop(true),
              child: const Text('تأكيد الإلغاء'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _cancelSending = true);
    try {
      await widget.api.cancelOrder(orderId: widget.orderId, customerId: cid, reason: reason.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('cancel_window_closed')
          ? 'لم يعد بإمكانك إلغاء الطلب. راجع الإدارة في قسم الدردشة أو اتصال.'
          : 'فشل إلغاء الطلب: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _cancelSending = false);
    }
  }

  String statusName(int s) {
    const names = ['جديد','تم التأكيد','قيد التجهيز','جاهز للاستلام','مع السائق','تم التسليم','ملغي'];
    if (s >= 0 && s < names.length) return names[s];
    if (s == 7) return 'تم القبول';
    return '$s';
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

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if ((prep == null || prep == 0) && (del == null || del == 0) && (expected == null || expected.isEmpty)) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, color: cs.primary, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'لم يتم تحديد الوقت المتوقع بعد. سيظهر هنا عند تحديده من الإدارة.',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time_rounded, color: cs.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'الوقت المتوقع لوصول الطلب',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
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
                Text(remaining <= 0 ? 'قيد التحديث' : '${remaining}د'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _showRatingDialog(int orderId, {required bool forRestaurant}) async {
    _stars = 5;
    _commentCtrl.text = '';

    // Local state for the bottom sheet to avoid double-submit.
    bool sending = false;

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
                  Text(forRestaurant ? 'قيّم المطعم' : 'قيّم السائق', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
                    onPressed: sending ? null : () async {
                      if (sending) return;
                      setLocal(() => sending = true);

                      try {
                        if (forRestaurant) {
                          await widget.api.rateRestaurant(
                            orderId: orderId,
                            customerId: widget.state.customerId!,
                            stars: _stars,
                            comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
                          );
                        } else {
                          await widget.api.rateDriver(
                            orderId: orderId,
                            customerId: widget.state.customerId!,
                            stars: _stars,
                            comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
                          );
                        }
                        // Re-enable button immediately (before closing)
                        setLocal(() => sending = false);
                        if (mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التقييم ✅')));
                        }
                        await _load();
                      } catch (e) {
                        // Re-enable button on failure
                        setLocal(() => sending = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ التقييم: $e')));
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

  Future<void> _showMandatoryRatingDialog({required int orderId, required bool rateRestaurant, required bool rateDriver}) async {
    if (!mounted) return;
    int restaurantStars = 5;
    int driverStars = 5;
    final comment = TextEditingController();

    void closeDialog(BuildContext dialogCtx) {
      // Defensive: some navigator stacks (especially Flutter Web) may report
      // canPop() as false even though the dialog is on top.
      try {
        Navigator.of(dialogCtx, rootNavigator: true).pop();
        return;
      } catch (_) {}
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
    }

    Widget starRow(int value, void Function(int) setValue, ColorScheme cs) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          final s = i + 1;
          return IconButton(
            onPressed: () => setValue(s),
            icon: Icon(
              s <= value ? Icons.star_rounded : Icons.star_border_rounded,
              color: s <= value ? cs.secondary : cs.onSurfaceVariant.withOpacity(0.5),
              size: 36,
            ),
          );
        }),
      );
    }

    bool sending = false;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: cs.surface,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 44, 20, 16),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.star_rounded, color: cs.primary, size: 26),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('تقييم الطلب', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.onSurface)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('ساعدنا بتقييم الخدمة لتحسين الجودة. (اختياري)', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 18),
                          if (rateRestaurant) ...[
                            Text('تقييم المطعم', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            const SizedBox(height: 6),
                            starRow(restaurantStars, (v) => setState(() => restaurantStars = v), cs),
                            const SizedBox(height: 14),
                          ],
                          if (rateDriver) ...[
                            Text('تقييم السائق', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            const SizedBox(height: 6),
                            starRow(driverStars, (v) => setState(() => driverStars = v), cs),
                            const SizedBox(height: 14),
                          ],
                          TextField(
                            controller: comment,
                            decoration: InputDecoration(
                              hintText: 'اكتب تعليقك (اختياري)',
                              filled: true,
                              fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            maxLines: 3,
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: sending
                                  ? null
                                  : () {
                                      if (sending) return;
                                      if (!ctx.mounted) return;
                                      sending = true;
                                      closeDialog(ctx);
                                      Future.microtask(() async {
                                        try {
                                          final cid = widget.state.customerId;
                                          if (cid == null) return;
                                          await widget.api.submitOrderRating(
                                            orderId: orderId,
                                            customerId: cid,
                                            restaurantRate: restaurantStars,
                                            driverRate: rateDriver ? driverStars : 5,
                                            comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
                                          );
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التقييم ✅')));
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ التقييم: $e')));
                                        }
                                      });
                                    },
                              icon: const Icon(Icons.check_circle_outline, size: 22),
                              label: const Text('إرسال التقييم'),
                              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              closeDialog(ctx);
                            },
                            child: Text('لاحقاً', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () {
                        widget.state.markRatingDismissed(orderId);
                        closeDialog(ctx);
                      },
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHighest),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    comment.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BrandTitle(state: widget.state, suffix: 'تفاصيل الطلب #${widget.orderId}'),
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
    final rating = o['orderRating'];
    final driverStars = (rating is Map) ? rating['driverRate'] : null;
    final restaurantStars = (rating is Map) ? rating['restaurantRate'] : null;
    final canRateDriver = status == 5 && widget.state.customerId != null && (o['driverId'] != null) && (driverStars == null);
    final canRateRestaurant = status == 5 && widget.state.customerId != null && (restaurantStars == null);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final totalStr = (o['total'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00';
    final statusStr = statusName((o['currentStatus'] ?? 0) as int);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.receipt_long_rounded, color: cs.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الحالة: $statusStr',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الإجمالي: $totalStr',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        SupportCard(state: widget.state),
        const SizedBox(height: 12),

        if ((o['canEdit'] == true && o['orderEditableUntilUtc'] != null) || (o['canCancel'] == true))
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_note_rounded, color: cs.primary, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'إدارة الطلب',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'تعديل خلال 5 دقائق • إلغاء خلال دقيقة واحدة من الإرسال.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (o['canEdit'] == true && o['orderEditableUntilUtc'] != null)
                      FilledButton.icon(
                        onPressed: () {
                  try {
                    final until = DateTime.parse(o['orderEditableUntilUtc'].toString());

                    // Extra safety: if the server window already ended (stale UI), block and guide to support.
                    if (DateTime.now().toUtc().isAfter(until.toUtc())) {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('انتهت مدة تعديل الطلب'),
                          content: const Text('لم يعد بإمكانك تعديل الطلب.\nراجع الإدارة في قسم الدردشة أو اتصال.'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => ComplaintsScreen(api: widget.api, state: widget.state)),
                                );
                              },
                              child: const Text('الدردشة'),
                            ),
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق')),
                          ],
                        ),
                      );
                      return;
                    }

                    final lat = (o['deliveryLat'] is num) ? (o['deliveryLat'] as num).toDouble() : null;
                    final lng = (o['deliveryLng'] is num) ? (o['deliveryLng'] as num).toDouble() : null;
                    final addr = (o['deliveryAddress'] ?? '').toString();
                    final cartItems = items.map((x) {
                      final m = Map<String, dynamic>.from(x as Map);
                      return CartItem(
                        key: '${m['productId']}-${m['optionsSnapshot'] ?? ''}-${DateTime.now().millisecondsSinceEpoch}',
                        productId: (m['productId'] ?? 0) as int,
                        name: (m['productNameSnapshot'] ?? '').toString(),
                        unitPrice: ((m['unitPriceSnapshot'] as num?)?.toDouble() ?? 0),
                        qty: (m['quantity'] ?? 1) as int,
                        optionsSnapshot: (m['optionsSnapshot'] ?? '').toString(),
                        optionsLabel: 'خيارات محفوظة',
                      );
                    }).toList();

                    widget.state.beginEditOrder(
                      orderId: widget.orderId,
                      untilUtc: until.toUtc(),
                      items: cartItems,
                      notes: (o['notes'] ?? '').toString(),
                    );

                    if (lat != null && lng != null) {
                      widget.state.setDeliveryLocation(
                        lat: lat,
                        lng: lng,
                        address: addr.trim().isEmpty ? widget.state.defaultAddress : addr,
                      );
                    }

                    // UX: Immediately go to cart for editing.
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CartScreen(api: widget.api, state: widget.state)),
                    );
                  } catch (_) {}
                        },
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        label: const Text('تعديل'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    if (o['canEdit'] == true && o['canCancel'] == true) const SizedBox(width: 10),
                    if (o['canCancel'] == true)
                      OutlinedButton.icon(
                        onPressed: _cancelSending ? null : _cancelOrder,
                        icon: _cancelSending
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cancel_outlined, size: 20),
                        label: Text(_cancelSending ? 'جاري...' : 'إلغاء'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(color: Theme.of(context).colorScheme.error),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

        if (o['canEdit'] != true && o['orderEditableUntilUtc'] != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_clock_rounded, color: cs.onSurfaceVariant, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'انتهت مدة تعديل الطلب',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'يمكنك التواصل مع الإدارة عبر الدردشة أو الاتصال لتعديل الطلب.',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ComplaintsScreen(api: widget.api, state: widget.state)),
                    );
                  },
                  child: const Text('الدردشة'),
                ),
              ],
            ),
          ),

        if (o['canCancel'] != true)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الإلغاء متاح لمدة دقيقة واحدة فقط',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'إذا احتجت إلغاء بعد انتهاء المهلة، تواصل مع الإدارة عبر الدردشة أو الاتصال.',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComplaintsScreen(api: widget.api, state: widget.state)));
                  },
                  child: const Text('الدردشة'),
                ),
              ],
            ),
          ),

        _etaCard(o),
        const SizedBox(height: 12),
        if ((o['deliveryAddress'] ?? '').toString().trim().isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'موقع التوصيل',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        o['deliveryAddress'].toString(),
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),
        Text(
          'الأصناف',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
        ),
        const SizedBox(height: 10),
        ...items.map((it) {
          final m = Map<String, dynamic>.from(it as Map);
          final qty = (m['quantity'] as num?)?.toInt() ?? 1;
          final name = (m['productNameSnapshot'] ?? '').toString();
          final price = (m['unitPriceSnapshot'] as num?)?.toDouble() ?? 0;
          final opts = _humanOptions(m['optionsSnapshot']?.toString()).trim();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (opts.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          opts,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  'x$qty  •  ${(price * qty).toStringAsFixed(0)} ل.س',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 20),
        Text(
          'سجل الحالة',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
        ),
        const SizedBox(height: 10),
        if (history.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'لا يوجد سجل بعد',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
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
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusName(st),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (comment.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            comment,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    timeText,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 12),
        if (status == 5 && widget.state.customerId != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: cs.primary, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'تم تسليم الطلب ✅',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'ساعدنا بتقييم الخدمة لتحسين الجودة.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (canRateRestaurant)
                      FilledButton.icon(
                        onPressed: () => _showRatingDialog(widget.orderId, forRestaurant: true),
                        icon: const Icon(Icons.storefront_rounded, size: 20),
                        label: const Text('تقييم المطعم'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    if (canRateDriver)
                      FilledButton.icon(
                        onPressed: () => _showRatingDialog(widget.orderId, forRestaurant: false),
                        icon: const Icon(Icons.directions_bike_rounded, size: 20),
                        label: const Text('تقييم السائق'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (rating != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تقييماتك',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.storefront_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'المطعم: ${(restaurantStars ?? '—').toString()} / 5',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if ((rating['restaurantComment'] ?? '').toString().trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 28),
                    child: Text(
                      rating['restaurantComment'].toString(),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.directions_bike_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'السائق: ${(driverStars ?? '—').toString()} / 5',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if ((rating['driverComment'] ?? '').toString().trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 28),
                    child: Text(
                      rating['driverComment'].toString(),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
