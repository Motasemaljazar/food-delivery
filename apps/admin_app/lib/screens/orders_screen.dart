import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.api, required this.state});
  final ApiClient api;
  final AppState state;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool loading = true;
  String? error;
  List<dynamic> orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if(widget.state.customerId==null){ setState((){loading=false; orders=[];}); return; }
    setState((){loading=true; error=null;});
    try{
      orders = await widget.api.listOrders(widget.state.customerId!);
    }catch(e){
      error = e.toString();
    }finally{ if(mounted) setState(()=>loading=false); }
  }

  String _etaLine(Map<String, dynamic> m) {
    // Prefer server fields, fallback to realtime cache
    final expected = m['expectedDeliveryAtUtc'] ?? widget.state.orderEtaCache[m['id'] as int]?['expectedDeliveryAtUtc'];
    if (expected == null) return '';
    try {
      final dt = DateTime.parse(expected.toString()).toLocal();
      final diff = dt.difference(DateTime.now()).inMinutes;
      if (diff <= 0) return '\nالوقت المتوقع: غير متاح';
      return '\nالوقت المتوقع: $diff د';
    } catch (_) {
      return '';
    }
  }

  String statusName(int s) {
    const list = ['New','Confirmed','Preparing','ReadyForPickup','WithDriver','Delivered','Cancelled'];
    return (s >= 0 && s < list.length) ? list[s] : '$s';
  }

  @override
  Widget build(BuildContext context) {
    if(loading) return const Center(child: CircularProgressIndicator());
    if(error!=null) return Center(child: Text(error!));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if(orders.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا يوجد طلبات بعد'))),
          ...orders.map((o){
            final m = o as Map<String, dynamic>;
            return Card(
              child: ListTile(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OrderDetailsScreen(api: widget.api, state: widget.state, orderId: m['id'] as int)),
                ).then((_) => _load()),
                title: Text('طلب #${m['id']}'),
                subtitle: Text('الحالة: ${statusName(m['currentStatus'] as int)}${_etaLine(m)}'),
                trailing: Text((m['total'] as num).toDouble().toStringAsFixed(2)),
              ),
            );
          })
        ],
      ),
    );
  }
}
