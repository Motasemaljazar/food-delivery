import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/app_state.dart';
import '../services/api.dart';

String _absUrl(String baseUrl, String? url) {
  if (url == null || url.trim().isEmpty) return '';
  final u = url.trim();
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final b = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  final p = u.startsWith('/') ? u : '/$u';
  return '$b$p';
}

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({
    super.key,
    required this.api,
    required this.state,
    required this.product,
    required this.categoryId,
    required this.offer,
  });

  final ApiClient api;
  final AppState state;
  final Map<String, dynamic> product;
  final int categoryId;
  final Map<String, dynamic>? offer;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  int qty = 1;
  int? selectedVariantId;
  final Set<int> selectedAddonIds = <int>{};
  final noteCtrl = TextEditingController();

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  double get _basePrice => (widget.product['price'] as num).toDouble();

  List<Map<String, dynamic>> get _variants {
    final raw = widget.product['variants'];
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<Map<String, dynamic>> get _addons {
    final raw = widget.product['addons'];
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Map<String, dynamic>? get _selectedVariant {
    if (selectedVariantId == null) return null;
    return _variants.where((v) => v['id'] == selectedVariantId).cast<Map<String, dynamic>?>().firstWhere((v) => v != null, orElse: () => null);
  }

  double get _variantDelta {
    final v = _selectedVariant;
    if (v == null) return 0;
    return (v['priceDelta'] as num).toDouble();
  }

  double get _addonsSum {
    double s = 0;
    for (final a in _addons) {
      if (selectedAddonIds.contains(a['id'] as int)) {
        s += (a['price'] as num).toDouble();
      }
    }
    return s;
  }

  double get _unitPrice => _basePrice + _variantDelta + _addonsSum;

  String _optionsLabel() {
    final parts = <String>[];
    final v = _selectedVariant;
    if (v != null) parts.add(v['name'].toString());
    if (selectedAddonIds.isNotEmpty) {
      final names = _addons
          .where((a) => selectedAddonIds.contains(a['id'] as int))
          .map((a) => a['name'].toString())
          .toList();
      if (names.isNotEmpty) parts.add('إضافات: ${names.join('، ')}');
    }
    final note = noteCtrl.text.trim();
    if (note.isNotEmpty) parts.add('ملاحظة');
    if (parts.isEmpty) return 'بدون إضافات';
    return parts.join(' • ');
  }

  String _optionsSnapshot() {
    final note = noteCtrl.text.trim();
    return jsonEncode({
      'variantId': selectedVariantId,
      'addonIds': selectedAddonIds.toList()..sort(),
      'note': note.isEmpty ? null : note,
    });
  }

  Widget _image(String url, {double? height}) {
    if (url.trim().isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height,
            color: Colors.black12,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        errorBuilder: (context, _, __) => Container(
          height: height,
          color: Colors.black12,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }

  Widget _qtyStepper(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: qty <= 1 ? null : () => setState(() => qty -= 1),
            icon: const Icon(Icons.remove),
          ),
          Text('$qty', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          IconButton(
            onPressed: () => setState(() => qty += 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = widget.api.baseUrl;
    final imagesRaw = (widget.product['images'] is Iterable)
        ? (widget.product['images'] as Iterable).map((e) => e?.toString() ?? '').toList()
        : <String>[];
    final images = imagesRaw.map((u) => _absUrl(baseUrl, u)).where((u) => u.isNotEmpty).toList();

    final offer = widget.offer;
    final offerLabel = () {
      if (offer == null) return null;
      final discountType = offer['discountType']?.toString();
      final val = (offer['value'] is num) ? (offer['value'] as num).toDouble() : 0;
      if (discountType == 'Percent') return 'خصم $val%';
      return 'خصم ${val.toStringAsFixed(0)} ل.س';
    }();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product['name'].toString()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                if (images.isNotEmpty)
                  PageView.builder(
                    itemCount: images.length,
                    itemBuilder: (context, i) => _image(images[i], height: 260),
                  )
                else
                  _image('', height: 260),
                if (offerLabel != null)
                  PositionedDirectional(
                    top: 12,
                    start: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [BoxShadow(blurRadius: 10, color: Color(0x22000000), offset: Offset(0, 4))],
                      ),
                      child: Text(offerLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.product['name'].toString(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${_unitPrice.toStringAsFixed(0)} ل.س',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if ((widget.product['description'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(widget.product['description'].toString(), style: Theme.of(context).textTheme.bodyLarge),
          ],
          const SizedBox(height: 18),

          if (_variants.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الاختيار', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ..._variants.map((v) {
                      final id = v['id'] as int;
                      final delta = (v['priceDelta'] as num).toDouble();
                      final label = delta == 0 ? v['name'].toString() : '${v['name']} (+${delta.toStringAsFixed(0)})';
                      return RadioListTile<int>(
                        value: id,
                        // ignore: deprecated_member_use
                        groupValue: selectedVariantId,
                        // ignore: deprecated_member_use
                        onChanged: (x) => setState(() => selectedVariantId = x),
                        title: Text(label),
                      );
                    }),
                    if (selectedVariantId != null)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () => setState(() => selectedVariantId = null),
                          icon: const Icon(Icons.clear),
                          label: const Text('إزالة الاختيار'),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          if (_addons.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إضافات', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ..._addons.map((a) {
                      final id = a['id'] as int;
                      final price = (a['price'] as num).toDouble();
                      return CheckboxListTile(
                        value: selectedAddonIds.contains(id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selectedAddonIds.add(id);
                          } else {
                            selectedAddonIds.remove(id);
                          }
                        }),
                        title: Text(a['name'].toString()),
                        subtitle: Text('+${price.toStringAsFixed(0)}'),
                      );
                    }),
                  ],
                ),
              ),
            ),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ملاحظة على الصنف (اختياري)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'مثال: بدون بصل، حار…',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              _qtyStepper(context),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final snapshot = _optionsSnapshot();
                    final label = _optionsLabel();
                    for (var i = 0; i < qty; i++) {
                      widget.state.addToCartWithOptions(
                        productId: widget.product['id'] as int,
                        name: widget.product['name'].toString(),
                        unitPrice: _unitPrice,
                        optionsSnapshot: snapshot,
                        optionsLabel: label,
                      );
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تمت الإضافة إلى السلة')),
                    );
                  },
                  child: Text('أضف للسلة • ${(qty * _unitPrice).toStringAsFixed(0)} ل.س'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
