import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import 'location_picker_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key, required this.api, required this.state});
  final ApiClient api;
  final AppState state;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _notes = TextEditingController();
  final _coupon = TextEditingController();
  bool loading = false;
  String? msg;

  bool couponLoading = false;
  String? couponMessage;
  double couponDiscount = 0;
  String? appliedCoupon;

  double get deliveryFee => widget.state.deliveryFeeValue;
  double get subtotal => widget.state.cartSubtotal;
  double get total => (subtotal - couponDiscount).clamp(0, double.infinity) + deliveryFee;

  Future<void> applyCoupon() async {
    if (widget.state.customerId == null) {
      setState(() => couponMessage = 'يرجى تسجيل البيانات أولاً');
      return;
    }
    final code = _coupon.text.trim();
    if (code.isEmpty) {
      setState(() {
        appliedCoupon = null;
        couponDiscount = 0;
        couponMessage = null;
      });
      return;
    }
    setState(() {
      couponLoading = true;
      couponMessage = null;
    });
    try {
      final res = await widget.api.validateCoupon(customerId: widget.state.customerId!, code: code, subtotal: subtotal);
      final valid = res['valid'] == true;
      setState(() {
        appliedCoupon = valid ? code : null;
        couponDiscount = valid && res['discount'] is num ? (res['discount'] as num).toDouble() : 0;
        couponMessage = res['message']?.toString();
      });
    } catch (e) {
      setState(() {
        appliedCoupon = null;
        couponDiscount = 0;
        couponMessage = e.toString();
      });
    } finally {
      if (mounted) setState(() => couponLoading = false);
    }
  }

  Future<void> checkout() async {
    if(widget.state.customerId==null){ setState(()=>msg='يرجى تسجيل البيانات أولاً'); return; }
    if(widget.state.cart.isEmpty){ setState(()=>msg='السلة فارغة'); return; }
    setState(() { loading = true; msg = null; });
    try{
      final items = widget.state.cart.map((c)=>{'productId':c.productId,'quantity':c.qty,'optionsSnapshot':c.optionsSnapshot}).toList();
      final id = await widget.api.createOrder(
        customerId: widget.state.customerId!,
        items: items,
        notes: _notes.text.trim().isEmpty?null:_notes.text.trim(),
        couponCode: appliedCoupon,
        deliveryLat: widget.state.defaultLat,
        deliveryLng: widget.state.defaultLng,
        deliveryAddress: widget.state.defaultAddress,
      );
      widget.state.clearCart();
      setState(()=>msg='تم إنشاء الطلب رقم #$id');
    }catch(e){
      setState(()=>msg=e.toString());
    }finally{
      if(mounted) setState(()=>loading=false);
    }
  }

  Future<void> _changeDeliveryLocation() async {
    final lat = widget.state.defaultLat ?? widget.state.restaurantLat;
    final lng = widget.state.defaultLng ?? widget.state.restaurantLng;
    final res = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialLat: lat, initialLng: lng),
      ),
    );
    if (res is LatLngResult) {
      widget.state.setDeliveryLocation(
        lat: res.lat,
        lng: res.lng,
        address: widget.state.defaultAddress,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('موقع التوصيل'),
                subtitle: Text(
                  (widget.state.defaultAddress != null && widget.state.defaultAddress!.trim().isNotEmpty)
                      ? widget.state.defaultAddress!
                      : 'تحديد على الخريطة أو إدخال يدوي',
                ),
                trailing: OutlinedButton(
                  onPressed: _changeDeliveryLocation,
                  child: const Text('تعديل'),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ...widget.state.cart.map((c)=>Card(
                    child: ListTile(
                      title: Text(c.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (c.optionsLabel.trim().isNotEmpty) Text(c.optionsLabel),
                          Text('سعر القطعة: ${c.unitPrice.toStringAsFixed(0)}'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: ()=>widget.state.setQty(c.key, c.qty-1), icon: const Icon(Icons.remove)),
                          Text('${c.qty}'),
                          IconButton(onPressed: ()=>widget.state.setQty(c.key, c.qty+1), icon: const Icon(Icons.add)),
                          IconButton(onPressed: ()=>widget.state.removeFromCart(c.key), icon: const Icon(Icons.delete)),
                        ],
                      ),
                    ),
                  )),
                  if(widget.state.cart.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('السلة فارغة')),
                    ),
                ],
              ),
            ),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'ملاحظات على الطلب (اختياري)')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _coupon,
                    decoration: const InputDecoration(labelText: 'كود الخصم (اختياري)'),
                    onSubmitted: (_) => applyCoupon(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: couponLoading ? null : applyCoupon,
                  child: couponLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تطبيق'),
                ),
              ],
            ),
            if (couponMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  couponMessage!,
                  style: TextStyle(color: (appliedCoupon != null) ? Colors.green : Colors.red),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(children: [const Expanded(child: Text('المجموع الفرعي')), Text('${subtotal.toStringAsFixed(0)} ل.س')]),
                    const SizedBox(height: 6),
                    Row(children: [const Expanded(child: Text('الخصم')), Text(couponDiscount == 0 ? '-' : '-${couponDiscount.toStringAsFixed(0)} ل.س')]),
                    const SizedBox(height: 6),
                    Row(children: [const Expanded(child: Text('رسوم التوصيل')), Text('${deliveryFee.toStringAsFixed(0)} ل.س')]),
                    const Divider(height: 18),
                    Row(
                      children: [
                        Expanded(child: Text('الإجمالي', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                        Text('${total.toStringAsFixed(0)} ل.س', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: loading ? null : checkout,
                        child: loading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('تأكيد الطلب'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if(msg!=null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  msg!,
                  style: TextStyle(color: msg!.contains('تم') ? Colors.green : Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
