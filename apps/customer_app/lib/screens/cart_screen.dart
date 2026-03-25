import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:url_launcher/url_launcher.dart';

import '../models/app_state.dart';
import '../services/api.dart';
import 'location_picker_screen.dart';
import 'complaints_screen.dart';

/// Market-ready cart screen:
/// - No saved addresses list inside cart (location is confirmed on map).
/// - Notes field.
/// - Checkout opens map (GPS -> map -> confirm).
/// - Edit window (5 minutes) is enforced silently (no "5 minutes" message).
class CartScreen extends StatefulWidget {
  const CartScreen({super.key, required this.api, required this.state});
  final ApiClient api;
  final AppState state;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _notes = TextEditingController();
  bool _loading = false;
  String? _message;
  Timer? _ticker;
  bool _locLoading = false;
  bool _addressesLoaded = false;
  /// بعد تحديث سعر التوصيل (نقرة أولى) يصبح true؛ النقرة الثانية ترسل الطلب. يُعاد false عند تغيير الموقع.
  bool _deliveryFeeRefreshedForCheckout = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.state.editingNotes != null) {
      _notes.text = widget.state.editingNotes!;
    }
    _loadAddressesIfNeeded();
  }

  Future<void> _loadAddressesIfNeeded() async {
    final cid = widget.state.customerId;
    if (cid == null || _addressesLoaded) return;
    try {
      final res = await widget.api.getAddresses(cid);
      final list = res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      widget.state.setSavedAddresses(list);
      if (mounted) setState(() => _addressesLoaded = true);
    } catch (_) {
      if (mounted) setState(() => _addressesLoaded = true);
    }
  }

  /// يحدّث رسوم التوصيل بناءً على defaultLat/defaultLng الحالي ويحدّث الواجهة.
  Future<void> _updateDeliveryFeeFromLocation() async {
    final lat = widget.state.defaultLat;
    final lng = widget.state.defaultLng;
    if (lat == null || lng == null) return;
    try {
      final estimate = await widget.api.deliveryEstimate(lat, lng);
      final fee = (estimate['deliveryFee'] is num) ? (estimate['deliveryFee'] as num).toDouble() : 0.0;
      widget.state.setDeliveryFee(fee);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _notes.dispose();
    super.dispose();
  }

  double get _deliveryFee => widget.state.deliveryFeeValue;
  double get _subtotal => widget.state.cartSubtotal;
  double get _total => _subtotal + _deliveryFee;
  /// عند السلة الفارغة نعرض "تأكيد الطلب" حتى لا يتحول الزر إلى "حدد موقع التوصيل" بعد إرسال الطلب.
  bool get _hasLocationForCheckout =>
      widget.state.cart.isEmpty ||
      (widget.state.defaultLat != null && widget.state.defaultLng != null);

  String _newIdempotencyKey() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _formatRemaining(Duration? d) {
    if (d == null) return '';
    final totalSeconds = d.inSeconds;
    if (totalSeconds <= 0) return '';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<Position> _getCurrentPositionOrThrow() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('يرجى تفعيل خدمة الموقع (GPS)');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw Exception('يرجى السماح بإذن الموقع للتطبيق');
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('إذن الموقع مرفوض نهائياً. افتح إعدادات الهاتف وفعّل إذن الموقع');
    }

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _checkout() async {
    if (widget.state.customerId == null) {
      setState(() => _message = 'يرجى إدخال بياناتك أولاً');
      return;
    }

    // If edit window is closed, block editing and guide the customer to contact admin.
    if (widget.state.isEditingOrder && (widget.state.editingRemaining?.inSeconds ?? 0) <= 0) {
      if (mounted) {
        await _showEditClosedDialog();
      }
      widget.state.endEditOrder();
      setState(() => _message = 'لم يعد بإمكانك تعديل الطلب. راجع الإدارة في قسم الدردشة أو اتصال.');
      return;
    }

    if (widget.state.cart.isEmpty) {
      setState(() => _message = 'السلة فارغة');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      // للطلب الجديد: إن لم يكن الموقع معيّناً نفتح الخريطة؛ عند تعيين الموقع نحدّث السلة برسوم التوصيل ونرجع دون إرسال. عند الضغط على تأكيد الطلب مرة ثانية (والموقع معيّن) نرسل الطلب.
      LatLngResult? picked;
      if (!widget.state.isEditingOrder) {
        final hasLocation = widget.state.defaultLat != null && widget.state.defaultLng != null;
        if (!hasLocation) {
          final pos = await _getCurrentPositionOrThrow();
          picked = await Navigator.of(context).push<LatLngResult>(
            MaterialPageRoute(
              builder: (_) => LocationPickerScreen(initialLat: pos.latitude, initialLng: pos.longitude),
            ),
          );
          if (picked == null) {
            setState(() => _message = 'تم إلغاء تحديد الموقع');
            return;
          }
          widget.state.setDeliveryLocation(
            lat: picked.lat,
            lng: picked.lng,
            address: widget.state.defaultAddress ?? 'تم تحديد الموقع على الخريطة',
          );
          final estimate = await widget.api.deliveryEstimate(picked.lat, picked.lng);
          final fee = (estimate['deliveryFee'] is num) ? (estimate['deliveryFee'] as num).toDouble() : 0.0;
          widget.state.setDeliveryFee(fee);
          if (mounted) {
            setState(() => _message = null);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم تعيين الموقع. راجع السعر ثم اضغط تأكيد الطلب للإرسال.'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
      }

      final items = widget.state.cart
          .map((c) => {
                'productId': c.productId,
                'quantity': c.qty,
                'optionsSnapshot': c.optionsSnapshot,
              })
          .toList();

      // للطلب الجديد: النقرة الأولى تحدّث سعر التوصيل فقط؛ النقرة الثانية ترسل الطلب.
      if (!widget.state.isEditingOrder) {
        final hasLocation = widget.state.defaultLat != null && widget.state.defaultLng != null;
        if (!hasLocation) {
          setState(() => _loading = false);
          setState(() => _message = 'يجب تحديد موقع التوصيل أولاً. اضغط تأكيد الطلب لفتح الخريطة.');
          return;
        }
        if (!_deliveryFeeRefreshedForCheckout) {
          await _updateDeliveryFeeFromLocation();
          if (!mounted) return;
          setState(() => _deliveryFeeRefreshedForCheckout = true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم تحديث سعر التوصيل. اضغط تأكيد الطلب مرة أخرى لإرسال الطلب.'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
      }

      if (widget.state.isEditingOrder) {
        final oid = widget.state.editingOrderId!;
        await widget.api.editOrder(
          orderId: oid,
          customerId: widget.state.customerId!,
          items: items,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          deliveryLat: widget.state.defaultLat,
          deliveryLng: widget.state.defaultLng,
          deliveryAddress: widget.state.defaultAddress,
        );
        widget.state.endEditOrder();
        widget.state.clearCart();
        setState(() => _message = 'تم تعديل الطلب #$oid');
        return;
      }

      final id = await widget.api.createOrder(
        customerId: widget.state.customerId!,
        idempotencyKey: _newIdempotencyKey(),
        items: items,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        addressId: null,
        deliveryLat: widget.state.defaultLat!,
        deliveryLng: widget.state.defaultLng!,
        deliveryAddress: widget.state.defaultAddress ?? 'تم تحديد الموقع على الخريطة',
      );

      widget.state.clearCart();
      widget.state.clearDeliveryForNextOrder();
      setState(() => _message = 'تم إرسال الطلب #$id');
    } catch (e) {
      final msg = e.toString();
      // If edit window closed, show a smooth UX dialog (market behavior)
      if (widget.state.isEditingOrder && msg.contains('edit_window_closed')) {
        if (mounted) await _showEditClosedDialog();
        widget.state.endEditOrder();
        setState(() => _message = 'لم يعد بإمكانك تعديل الطلب. راجع الإدارة في قسم الدردشة أو اتصال.');
      } else {
        setState(() => _message = msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Widget _buildLocationSection(ColorScheme cs) {
    final hasLocation = widget.state.defaultLat != null && widget.state.defaultLng != null;
    final saved = widget.state.savedAddresses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.location_on_outlined, color: cs.primary, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasLocation
                          ? ((widget.state.defaultAddress ?? '').trim().isEmpty ? 'تم تحديد الموقع على الخريطة' : widget.state.defaultAddress!)
                          : 'لم يتم تحديد موقع التوصيل',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: hasLocation ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasLocation)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'رسوم التوصيل: ${widget.state.deliveryFeeValue.toStringAsFixed(0)} ل.س',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _locLoading ? null : () async {
                  setState(() => _locLoading = true);
                  try {
                    final lat0 = widget.state.defaultLat;
                    final lng0 = widget.state.defaultLng;
                    LatLngResult? picked;
                    if (lat0 != null && lng0 != null) {
                      picked = await Navigator.of(context).push<LatLngResult>(
                        MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLat: lat0, initialLng: lng0)),
                      );
                    } else {
                      final gps = await _getCurrentPositionOrThrow();
                      picked = await Navigator.of(context).push<LatLngResult>(
                        MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLat: gps.latitude, initialLng: gps.longitude)),
                      );
                    }
                    if (picked != null) {
                      widget.state.setDeliveryLocation(
                        lat: picked.lat,
                        lng: picked.lng,
                        address: (widget.state.defaultAddress ?? '').trim().isEmpty ? 'تم تحديد الموقع على الخريطة' : widget.state.defaultAddress,
                      );
                      setState(() => _deliveryFeeRefreshedForCheckout = false);
                      await _updateDeliveryFeeFromLocation();
                    }
                  } catch (_) {}
                  if (mounted) setState(() => _locLoading = false);
                },
                child: _locLoading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('تعديل الموقع'),
              ),
            ],
          ),
        ),
        if (saved.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'عناويني المحفوظة',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          ...saved.map((a) {
            final lat = (a['latitude'] as num?)?.toDouble();
            final lng = (a['longitude'] as num?)?.toDouble();
            final title = (a['title'] ?? a['addressText'] ?? 'عنوان').toString();
            final addr = (a['addressText'] ?? a['address'] ?? '').toString();
            final isSelected = widget.state.selectedAddressId == (a['id'] as num?)?.toInt();
            final canSelect = lat != null && lng != null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: isSelected ? cs.primaryContainer.withOpacity(0.5) : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: canSelect
                      ? () async {
                          widget.state.selectAddress(a);
                          setState(() => _deliveryFeeRefreshedForCheckout = false);
                          await _updateDeliveryFeeFromLocation();
                          if (mounted) setState(() {});
                        }
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off_outlined,
                          color: canSelect ? cs.primary : cs.onSurfaceVariant.withOpacity(0.5),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
                              if (addr.trim().isNotEmpty)
                                Text(addr, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Future<void> _showEditClosedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
            if (widget.state.supportPhone.trim().isNotEmpty)
              ElevatedButton(
                onPressed: () async {
                  final phone = widget.state.supportPhone.trim();
                  final uri = Uri.parse('tel:$phone');
                  try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                  if (context.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('اتصال'),
              ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق')),
          ],
        );
      },
    );
  }

  Widget _qtyButton({required IconData icon, required VoidCallback onTap}) {
    return SizedBox(
      height: 34,
      width: 34,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withOpacity(0.04),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = _formatRemaining(widget.state.editingRemaining);
    final isEditing = widget.state.isEditingOrder;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'تعديل الطلب' : 'السلة'),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (isEditing && remaining.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('يمكن تعديل الطلب لفترة محدودة', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Text(remaining, style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),

                if (isEditing)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (widget.state.defaultAddress ?? '').trim().isEmpty
                                ? 'موقع التوصيل'
                                : widget.state.defaultAddress!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _locLoading
                              ? null
                              : () async {
                                  // Allow location edit within the edit window.
                                  if ((widget.state.editingRemaining?.inSeconds ?? 0) <= 0) {
                                    widget.state.endEditOrder();
                                    return;
                                  }
                                  setState(() => _locLoading = true);
                                  try {
                                    final lat0 = widget.state.defaultLat;
                                    final lng0 = widget.state.defaultLng;
                                    final pos = (lat0 != null && lng0 != null)
                                        ? LatLngResult(lat0, lng0)
                                        : null;
                                    final initial = pos;
                                    LatLngResult? picked;
                                    if (initial != null) {
                                      picked = await Navigator.of(context).push<LatLngResult>(
                                        MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLat: initial.lat, initialLng: initial.lng)),
                                      );
                                    } else {
                                      final gps = await _getCurrentPositionOrThrow();
                                      picked = await Navigator.of(context).push<LatLngResult>(
                                        MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLat: gps.latitude, initialLng: gps.longitude)),
                                      );
                                    }
                                    if (picked != null) {
                                      widget.state.setDeliveryLocation(
                                        lat: picked.lat,
                                        lng: picked.lng,
                                        address: (widget.state.defaultAddress ?? '').trim().isEmpty
                                            ? 'تم تحديد الموقع على الخريطة'
                                            : widget.state.defaultAddress,
                                      );
                                      await _updateDeliveryFeeFromLocation();
                                    }
                                  } catch (_) {
                                  } finally {
                                    if (mounted) setState(() => _locLoading = false);
                                  }
                                },
                          child: _locLoading
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('تعديل الموقع'),
                        )
                      ],
                    ),
                  ),
                if (isEditing && remaining.isNotEmpty) const SizedBox(height: 14),

                // للطلب الجديد: قسم الموقع + عناويني المحفوظة
                if (!isEditing && widget.state.customerId != null) ...[
                  _buildLocationSection(cs),
                  const SizedBox(height: 12),
                ],

                // Items
                if (widget.state.cart.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 40),
                        SizedBox(height: 10),
                        Text('السلة فارغة', style: TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  )
                else
                  ...widget.state.cart.map((it) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.black.withOpacity(0.06)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(it.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                                if (it.optionsLabel.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      it.optionsLabel,
                                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Text('${it.unitPrice.toStringAsFixed(0)} ل.س', style: const TextStyle(fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Row(
                            children: [
                              _qtyButton(
                                icon: Icons.remove,
                                onTap: () {
                                  final next = (it.qty - 1);
                                  if (next <= 0) {
                                    widget.state.removeFromCart(it.key);
                                  } else {
                                    widget.state.setQty(it.key, next);
                                  }
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text('${it.qty}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              ),
                              _qtyButton(
                                icon: Icons.add,
                                onTap: () => widget.state.setQty(it.key, it.qty + 1),
                              ),
                            ],
                          )
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 14),

                // Notes
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: TextField(
                    controller: _notes,
                    maxLines: 3,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'ملاحظات على الطلب (اختياري)',
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Totals
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: Column(
                    children: [
                      Row(children: [const Expanded(child: Text('المجموع', style: TextStyle(fontWeight: FontWeight.w800))), Text('${_subtotal.toStringAsFixed(0)} ل.س', style: const TextStyle(fontWeight: FontWeight.w900))]),
                      const SizedBox(height: 8),
                      Row(children: [const Expanded(child: Text('رسوم التوصيل', style: TextStyle(fontWeight: FontWeight.w800))), Text('${_deliveryFee.toStringAsFixed(0)} ل.س', style: const TextStyle(fontWeight: FontWeight.w900))]),
                      const Divider(height: 22),
                      Row(children: [const Expanded(child: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w900))), Text('${_total.toStringAsFixed(0)} ل.س', style: const TextStyle(fontWeight: FontWeight.w900))]),
                    ],
                  ),
                ),

                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w800)),
                ],

                const SizedBox(height: 18),

                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _checkout,
                    icon: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(isEditing ? Icons.save_outlined : (_hasLocationForCheckout ? Icons.check_circle_outline : Icons.location_on_outlined)),
                    label: Text(
                      isEditing
                          ? 'حفظ التعديل'
                          : (_hasLocationForCheckout ? 'تأكيد الطلب' : 'حدد موقع التوصيل'),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
