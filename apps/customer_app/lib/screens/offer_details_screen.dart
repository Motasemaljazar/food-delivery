import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/app_state.dart';
import '../services/api.dart';

class OfferDetailsScreen extends StatefulWidget {
  const OfferDetailsScreen(
      {super.key, required this.api, required this.state, required this.offer});

  final ApiClient api;
  final AppState state;
  final Map<String, dynamic> offer;

  @override
  State<OfferDetailsScreen> createState() => _OfferDetailsScreenState();
}

class _OfferDetailsScreenState extends State<OfferDetailsScreen> {
  int qty = 1;
  Map<String, dynamic>? _templateProduct;
  int? _selectedVariantId;
  final Set<int> _selectedAddonIds = <int>{};
  bool _loadingTemplate = false;

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadTemplateIfNeeded();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadTemplateIfNeeded() async {
    // Offers can optionally link to a product so we can reuse its variants/addons.
    // Support both the older single field (primaryProductId) and the newer list
    // (linkedProductIds). This makes offer options (مثل "بدون خس") work reliably.
    int? primaryProductId = (widget.offer['primaryProductId'] as int?);
    if (primaryProductId == null || primaryProductId <= 0) {
      final linked = widget.offer['linkedProductIds'];
      if (linked is List && linked.isNotEmpty) {
        final v = linked.first;
        final id = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (id != null && id > 0) primaryProductId = id;
      }
    }
    if (primaryProductId == null || primaryProductId <= 0) return;

    setState(() => _loadingTemplate = true);
    try {
      final menu = await widget.api.getMenu();
      final cats = (menu['categories'] as List?) ?? const [];
      Map<String, dynamic>? found;
      for (final c in cats) {
        final cc = Map<String, dynamic>.from(c as Map);
        final prods = (cc['products'] as List?) ?? const [];
        for (final p in prods) {
          final pp = Map<String, dynamic>.from(p as Map);
          final id = (pp['id'] as num?)?.toInt() ?? 0;
          if (id == primaryProductId) {
            found = pp;
            break;
          }
        }
        if (found != null) break;
      }
      if (mounted) setState(() => _templateProduct = found);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingTemplate = false);
    }
  }

  void _addToCart() {
    final id = (widget.offer['id'] as int?) ?? 0;
    final title = (widget.offer['title'] ?? 'عرض').toString();
    final priceBefore = _num(widget.offer['priceBefore']);
    final priceAfter = _num(widget.offer['priceAfter']);
    final effectivePrice =
        priceAfter > 0 ? priceAfter : (priceBefore > 0 ? priceBefore : 0);

    final optionsSnapshot = jsonEncode({
      'type': 'offer',
      'offerId': id,
      'templateProductId': (_templateProduct?['id'] as int?),
      'offerVariantId': _selectedVariantId,
      'offerAddonIds': _selectedAddonIds.toList()..sort(),
      // No offer-specific note; notes are handled per cart item from the cart screen.
      'note': null,
    });

    // Store offers as negative productId (see AppState/CartItem).
    final pid = -id;
    final labelParts = <String>[];
    if (_selectedVariantId != null) labelParts.add('خيار');
    if (_selectedAddonIds.isNotEmpty) labelParts.add('إضافات');
    final optionsLabel =
        labelParts.isEmpty ? 'عرض' : ('عرض • ' + labelParts.join(' • '));

    widget.state.addToCartWithOptions(
      productId: pid,
      name: title,
      unitPrice: effectivePrice.toDouble(),
      optionsSnapshot: optionsSnapshot,
      optionsLabel: optionsLabel,
    );

    // If user chose qty > 1, adjust the stored cart item qty.
    if (qty > 1) {
      final key = '$pid|$optionsSnapshot';
      widget.state.setQty(key, qty);
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تمت الإضافة إلى السلة')));
    setState(() {});
  }

  Widget _buildOptionSection(BuildContext context) {
    if (_loadingTemplate) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final p = _templateProduct;
    if (p == null) return const SizedBox.shrink();

    final variants = (p['variants'] as List?) ?? const [];
    final addons = (p['addons'] as List?) ?? const [];
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
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'خيارات العرض',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (variants.isNotEmpty) ...[
              Text(
                'الحجم / النوع',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final v in variants)
                    FilterChip(
                      label: Text((v as Map)['name'].toString()),
                      selected:
                          _selectedVariantId == (v['id'] as num?)?.toInt(),
                      onSelected: (_) {
                        setState(() {
                          final vid = (v['id'] as num?)?.toInt();
                          _selectedVariantId =
                              (_selectedVariantId == vid) ? null : vid;
                        });
                      },
                      selectedColor: cs.primaryContainer,
                      labelStyle: TextStyle(
                        fontWeight:
                            _selectedVariantId == (v['id'] as num?)?.toInt()
                                ? FontWeight.w700
                                : FontWeight.w500,
                        color: _selectedVariantId == (v['id'] as num?)?.toInt()
                            ? cs.onPrimaryContainer
                            : cs.onSurface,
                      ),
                      side: BorderSide(
                        color: _selectedVariantId == (v['id'] as num?)?.toInt()
                            ? cs.primary
                            : cs.outline.withOpacity(0.4),
                        width: _selectedVariantId == (v['id'] as num?)?.toInt()
                            ? 1.5
                            : 1,
                      ),
                    ),
                ],
              ),
              if (addons.isNotEmpty) const SizedBox(height: 16),
            ],
            if (addons.isNotEmpty) ...[
              Text(
                'الإضافات',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ...addons.map((a) {
                final aid = (a['id'] as num?)?.toInt();
                final isSelected =
                    aid != null && _selectedAddonIds.contains(aid);
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primaryContainer.withOpacity(0.5)
                        : cs.surfaceContainerLow.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) {
                      if (aid == null) return;
                      setState(() {
                        if (v == true)
                          _selectedAddonIds.add(aid);
                        else
                          _selectedAddonIds.remove(aid);
                      });
                    },
                    title: Text(
                      (a as Map)['name'].toString(),
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                    subtitle: (a['price'] != null)
                        ? Text(
                            '+${_num(a['price']).toStringAsFixed(0)} ل.س',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                    activeColor: cs.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
    final title = (widget.offer['title'] ?? 'عرض').toString();
    final desc = (widget.offer['description'] ?? '').toString().trim();
    final code = (widget.offer['code'] ?? '').toString().trim();
    final priceBefore = _num(widget.offer['priceBefore']);
    final priceAfter = _num(widget.offer['priceAfter']);

    final images = (widget.offer['images'] is List)
        ? (widget.offer['images'] as List)
        : const [];
    final img = images.isNotEmpty
        ? ((images.first as Map)['url'] ?? '').toString()
        : (widget.offer['imageUrl'] ?? '').toString();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final effectivePrice =
        (priceAfter > 0) ? priceAfter : (priceBefore > 0 ? priceBefore : 0.0);
    final hasDiscount =
        priceBefore > 0 && priceAfter > 0 && priceAfter < priceBefore;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              color: cs.surfaceContainerLow.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: img.trim().isEmpty
                          ? Container(
                              height: 220,
                              color: cs.surfaceContainerHighest,
                              child: Center(
                                child: Icon(Icons.image_outlined,
                                    size: 48, color: cs.onSurfaceVariant),
                              ),
                            )
                          : Image.network(
                              img,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 220,
                                color: cs.surfaceContainerHighest,
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      size: 48, color: cs.onSurfaceVariant),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    if (desc.isNotEmpty)
                      Text(
                        desc,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (code.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_2_rounded,
                                size: 20, color: cs.primary),
                            const SizedBox(width: 8),
                            Text(
                              'الكود: $code',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (hasDiscount) ...[
                          Text(
                            priceBefore.toStringAsFixed(0),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              decoration: TextDecoration.lineThrough,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          '${effectivePrice.toStringAsFixed(0)} ل.س',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildOptionSection(context),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed:
                                qty > 1 ? () => setState(() => qty--) : null,
                            icon: Icon(Icons.remove_rounded,
                                color:
                                    qty > 1 ? cs.primary : cs.onSurfaceVariant),
                          ),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '$qty',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => qty++),
                            icon: Icon(Icons.add_rounded, color: cs.primary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _addToCart,
                        icon: const Icon(Icons.add_shopping_cart_rounded,
                            size: 22),
                        label: const Text('إضافة للسلة'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
