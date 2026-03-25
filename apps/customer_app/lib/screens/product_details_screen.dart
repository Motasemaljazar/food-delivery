import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/app_state.dart';
import '../services/api.dart';
import '../widgets/brand_title.dart';

String _absUrl(String baseUrl, String? url) {
  if (url == null || url.trim().isEmpty) return '';
  final u = url.trim();
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final b = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final p = u.startsWith('/') ? u : '/$u';
  return '$b$p';
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow(
      {required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: enabled ? Colors.black54 : Colors.black26,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _FullScreenGallery extends StatefulWidget {
  const _FullScreenGallery(
      {required this.imageUrls, required this.initialIndex});
  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _c;
  int idx = 0;

  @override
  void initState() {
    super.initState();
    idx = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _c = PageController(initialPage: idx);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${idx + 1}/${widget.imageUrls.length}'),
      ),
      body: PageView.builder(
        controller: _c,
        itemCount: widget.imageUrls.length,
        onPageChanged: (i) => setState(() => idx = i),
        itemBuilder: (context, i) {
          return Center(
            child: InteractiveViewer(
              child: Image.network(
                widget.imageUrls[i],
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({
    super.key,
    required this.api,
    required this.state,
    required this.product,
    required this.categoryName,
  });

  final ApiClient api;
  final AppState state;
  final Map<String, dynamic> product;
  final String categoryName;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  int qty = 1;
  int? selectedVariantId;
  final Set<int> selectedAddonIds = <int>{};

  late final PageController _imgController;
  int _imgIndex = 0;

  @override
  void initState() {
    super.initState();
    _imgController = PageController();
  }

  @override
  void dispose() {
    _imgController.dispose();
    super.dispose();
  }

  void _openFullScreen(List<String> images, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _FullScreenGallery(imageUrls: images, initialIndex: initialIndex),
      ),
    );
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
    return _variants
        .where((v) => v['id'] == selectedVariantId)
        .cast<Map<String, dynamic>?>()
        .firstWhere((v) => v != null, orElse: () => null);
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
      if (names.isNotEmpty) parts.add('خيارات: ${names.join('، ')}');
    }
    if (parts.isEmpty) return 'بدون خيارات';
    return parts.join(' • ');
  }

  String _optionsSnapshot() {
    return jsonEncode({
      'variantId': selectedVariantId,
      'addonIds': selectedAddonIds.toList()..sort(),
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
            child:
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: qty <= 1 ? null : () => setState(() => qty -= 1),
            icon: Icon(Icons.remove_rounded, color: qty > 1 ? cs.primary : cs.onSurfaceVariant),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => qty += 1),
            icon: Icon(Icons.add_rounded, color: cs.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_variants.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.tune_rounded, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'الاختيار',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _variants.map((v) {
                  final id = v['id'] as int;
                  final delta = (v['priceDelta'] as num).toDouble();
                  final label = delta == 0
                      ? v['name'].toString()
                      : '${v['name']} (+${delta.toStringAsFixed(0)})';
                  final selected = selectedVariantId == id;
                  return FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setState(() => selectedVariantId = selected ? null : id),
                    selectedColor: cs.primaryContainer,
                    labelStyle: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                    side: BorderSide(
                      color: selected ? cs.primary : cs.outline.withOpacity(0.5),
                      width: selected ? 1.5 : 1,
                    ),
                  );
                }).toList(),
              ),
              if (selectedVariantId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => setState(() => selectedVariantId = null),
                      icon: Icon(Icons.clear_rounded, size: 18, color: cs.error),
                      label: Text('إزالة الاختيار', style: TextStyle(color: cs.error)),
                    ),
                  ),
                ),
              if (_addons.isNotEmpty) const SizedBox(height: 16),
            ],
            if (_addons.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'خيارات',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._addons.map((a) {
                final id = a['id'] as int;
                final price = (a['price'] as num).toDouble();
                final isSelected = selectedAddonIds.contains(id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primaryContainer.withOpacity(0.4)
                        : cs.surfaceContainerLow.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selectedAddonIds.add(id);
                      } else {
                        selectedAddonIds.remove(id);
                      }
                    }),
                    title: Text(
                      a['name'].toString(),
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                    subtitle: price > 0
                        ? Text(
                            '+${price.toStringAsFixed(0)} ل.س',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                    activeColor: cs.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = widget.api.baseUrl;
    // API returns images as: [{ id, url, sortOrder, isPrimary }, ...]
    final raw = (widget.product['images'] is List)
        ? (widget.product['images'] as List)
        : const <dynamic>[];
    final urls = raw
        .map((e) =>
            (e is Map ? (e['url'] ?? '').toString() : e?.toString() ?? ''))
        .map((u) => _absUrl(baseUrl, u))
        .where((u) => u.trim().isNotEmpty)
        .toList();
    final images = urls;

    return Scaffold(
      appBar: AppBar(
        title: BrandTitle(
            state: widget.state, suffix: widget.product['name'].toString()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                if (images.isNotEmpty)
                  PageView.builder(
                    controller: _imgController,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _imgIndex = i),
                    itemBuilder: (context, i) {
                      return InkWell(
                        onTap: () => _openFullScreen(images, i),
                        child: _image(images[i], height: 260),
                      );
                    },
                  )
                else
                  _image('', height: 260),

                if (images.length > 1) ...[
                  PositionedDirectional(
                    start: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _CarouselArrow(
                        icon: Icons.chevron_left,
                        enabled: _imgIndex > 0,
                        onTap: () {
                          if (_imgIndex > 0)
                            _imgController.previousPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut);
                        },
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _CarouselArrow(
                        icon: Icons.chevron_right,
                        enabled: _imgIndex < images.length - 1,
                        onTap: () {
                          if (_imgIndex < images.length - 1)
                            _imgController.nextPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut);
                        },
                      ),
                    ),
                  ),
                ],
                if (images.length > 1)
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(images.length, (i) {
                        final active = i == _imgIndex;
                        final cs = Theme.of(context).colorScheme;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active ? cs.primary : cs.onSurfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Builder(builder: (context) {
            final theme = Theme.of(context);
            final cs = theme.colorScheme;
            final price = _unitPrice;
            final current = (widget.product['price'] is num)
                ? (widget.product['price'] as num).toDouble()
                : price;
            final original =
                (widget.product['originalPrice'] as num?)?.toDouble();
            final hasDisc = original != null && original > current;
            final badge =
                (widget.product['discountBadge'] ?? '').toString().trim();
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product['name'].toString(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      if (hasDisc && badge.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badge,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${price.toStringAsFixed(0)} ل.س',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.primary,
                      ),
                    ),
                    if (hasDisc && _variantDelta == 0 && _addonsSum == 0)
                      Text(
                        '${original.toStringAsFixed(0)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
          if ((widget.product['description'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              widget.product['description'].toString(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_variants.isNotEmpty || _addons.isNotEmpty)
            _buildOptionsCard(context),
          const SizedBox(height: 16),
          Row(
            children: [
              _qtyStepper(context),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (widget.product['isAvailable'] == false)
                      ? null
                      : () {
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
                            const SnackBar(
                                content: Text('تمت الإضافة إلى السلة')),
                          );
                        },
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 22),
                  label: Text(
                    (widget.product['isAvailable'] == false)
                        ? 'غير متوفر'
                        : 'أضف للسلة • ${(qty * _unitPrice).toStringAsFixed(0)} ل.س',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
