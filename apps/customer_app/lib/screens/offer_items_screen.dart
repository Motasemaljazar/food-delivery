import 'package:flutter/material.dart';

import '../models/app_state.dart';
import '../services/api.dart';
import 'cart_screen.dart';
import 'product_details_screen.dart';

class OfferItemsScreen extends StatefulWidget {
  const OfferItemsScreen({super.key, required this.api, required this.state, required this.offer});

  final ApiClient api;
  final AppState state;
  final Map<String, dynamic> offer;

  @override
  State<OfferItemsScreen> createState() => _OfferItemsScreenState();
}

class _OfferItemsScreenState extends State<OfferItemsScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = const [];

  int _cartCount() => widget.state.cart.fold<int>(0, (s, it) => s + it.qty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _firstImageRaw(Map<String, dynamic> obj) {
    final imgs = obj['images'];
    if (imgs is List && imgs.isNotEmpty) {
      final first = imgs.first;
      if (first is Map) {
        final u = (first['url'] ?? first['path'] ?? '').toString();
        if (u.trim().isNotEmpty) return u;
      }
      final u2 = (first ?? '').toString();
      if (u2.trim().isNotEmpty) return u2;
    }
    return (obj['imageUrl'] ?? obj['image'] ?? obj['photoUrl'] ?? '').toString();
  }

  String _absUrl(String u) {
    final url = u.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${widget.api.baseUrl}$url';
    return '${widget.api.baseUrl}/$url';
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final id = (widget.offer['id'] as int?) ?? 0;
      final list = await widget.api.getOfferItems(id);
      items = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openCart() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CartScreen(api: widget.api, state: widget.state)),
    );
  }

  void _openProduct(Map<String, dynamic> p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(
          api: widget.api,
          state: widget.state,
          product: p,
          categoryName: 'العرض',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.offer['title'] ?? 'العرض').toString();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (_cartCount() > 0)
              IconButton(
                onPressed: _openCart,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_cart_outlined),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '${_cartCount()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : (error != null)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off, size: 42),
                          const SizedBox(height: 10),
                          Text('تعذر تحميل أصناف العرض\n$error', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
                        ],
                      ),
                    ),
                  )
                : (items.isEmpty)
                    ? const Center(child: Text('لا توجد أصناف مرتبطة بهذا العرض حالياً'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final p = items[i];
                          final img = _absUrl(_firstImageRaw(p));
                          return InkWell(
                            onTap: () => _openProduct(p),
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: img.isEmpty
                                          ? Container(width: 92, height: 76, color: Colors.black12, child: const Icon(Icons.image_outlined))
                                          : Image.network(img, width: 92, height: 76, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 92, height: 76, color: Colors.black12, child: const Icon(Icons.image_outlined))),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text((p['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                                          const SizedBox(height: 4),
                                          if (((p['description'] ?? '').toString()).trim().isNotEmpty)
                                            Text((p['description'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700)),
                                          const SizedBox(height: 6),
                                          Text('${(p['price'] ?? 0)} ل.س', style: const TextStyle(fontWeight: FontWeight.w800)),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_left),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
