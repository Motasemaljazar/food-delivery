// ignore_for_file: unused_element
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import 'product_details_screen.dart';
import 'cart_screen.dart';
import 'offer_details_screen.dart';
import '../widgets/ui/category_card.dart';
import '../widgets/ui/offer_card.dart';
import '../widgets/ui/product_grid_card.dart';

enum _SortMode { all, newest, popular, topRated }

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.api, required this.state});
  final ApiClient api;
  final AppState state;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  bool loading = true;
  String? error;

  // Market-ready search (local filtering of menu data)
  final TextEditingController _searchCtl = TextEditingController();
  String _q = '';

  List<Map<String, dynamic>> categories = const [];
  List<Map<String, dynamic>> offers = const [];
  List<Map<String, dynamic>> popular = const [];

  int? activeCategoryId;

  // Sort pills (below products) — matches the UI requested: الجميع، انضم حديثاً، شائع، أعلى تصنيف
  _SortMode _sortMode = _SortMode.all;

  // Filters
  bool _offersOnly = false;
  bool _availableOnly = false;
  double? _minPrice;
  double? _maxPrice;
  double _minRating = 0;

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() {
      final v = _searchCtl.text.trim();
      if (v == _q) return;
      setState(() => _q = v);
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  bool get _isSearching => _q.trim().isNotEmpty;

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
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
    return (obj['imageUrl'] ?? obj['image'] ?? obj['photoUrl'] ?? '')
        .toString();
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  void _quickAddOffer(Map<String, dynamic> offer) {
    final id = _toInt(offer['id']);
    if (id <= 0) return;

    final title = (offer['title'] ?? 'عرض').toString();
    final priceBefore = _num(offer['priceBefore']);
    final priceAfter = _num(offer['priceAfter']);
    final double effectivePrice =
        priceAfter > 0 ? priceAfter : (priceBefore > 0 ? priceBefore : 0.0);

    final optionsSnapshot = jsonEncode({
      'type': 'offer',
      'offerId': id,
      'templateProductId': null,
      'offerVariantId': null,
      'offerAddonIds': const <int>[],
      // Notes are handled per cart-item from the cart screen (button for each item).
      'note': null,
    });

    // Store offers as negative productId (same logic as OfferDetailsScreen).
    final pid = -id;
    widget.state.addToCartWithOptions(
      productId: pid,
      name: title,
      unitPrice: effectivePrice,
      optionsSnapshot: optionsSnapshot,
      optionsLabel: 'عرض',
    );

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تمت الإضافة إلى السلة')));
    setState(() {});
  }

  List<Map<String, dynamic>> _allProducts() {
    final out = <Map<String, dynamic>>[];
    for (final c in categories) {
      final catId = _toInt(c['id']);
      final ps =
          (c['products'] is List) ? (c['products'] as List) : <dynamic>[];
      for (final p in ps) {
        final pm = Map<String, dynamic>.from(p as Map);
        if (pm['categoryId'] == null) pm['categoryId'] = catId;
        out.add(pm);
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _searchProducts() {
    final q = _q.toLowerCase();
    if (q.isEmpty) return const [];
    return _allProducts().where((p) {
      final name = ((p['name'] ?? '').toString()).toLowerCase();
      final desc = ((p['description'] ?? '').toString()).toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> _searchOffers() {
    final q = _q.toLowerCase();
    if (q.isEmpty) return const [];
    return offers
        .where((o) {
          final title = ((o['title'] ?? '').toString()).toLowerCase();
          final desc = ((o['description'] ?? '').toString()).toLowerCase();
          final code = ((o['code'] ?? '').toString()).toLowerCase();
          return title.contains(q) || desc.contains(q) || code.contains(q);
        })
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Set<int> _offerProductIds(Map<String, dynamic> o) {
    final ids = <int>{};
    final p = o['linkedProductIds'];
    if (p is List) {
      for (final x in p) {
        final v = (x is num) ? x.toInt() : int.tryParse(x.toString());
        if (v != null && v > 0) ids.add(v);
      }
    }
    return ids;
  }

  Set<int> _offerCategoryIds(Map<String, dynamic> o) {
    final ids = <int>{};
    final c = o['linkedCategoryIds'];
    if (c is List) {
      for (final x in c) {
        final v = (x is num) ? x.toInt() : int.tryParse(x.toString());
        if (v != null && v > 0) ids.add(v);
      }
    }
    // Backward compatible field (single)
    final pc = o['primaryCategoryId'];
    final pv = (pc is num) ? pc.toInt() : int.tryParse((pc ?? '').toString());
    if (pv != null && pv > 0) ids.add(pv);
    return ids;
  }

  bool _productAvailable(Map<String, dynamic> p) {
    final a = p['isAvailable'];
    if (a is bool) return a;
    // fallback on stock/availability flags
    final s = p['available'];
    if (s is bool) return s;
    return true;
  }

  double _productRating(Map<String, dynamic> p) {
    final r = p['avgRating'] ?? p['rating'];
    if (r is num) return r.toDouble();
    return double.tryParse((r ?? '0').toString()) ?? 0;
  }

  List<Map<String, dynamic>> _filteredProducts() {
    var items = _allProducts();

    // Category filter (chip)
    if (activeCategoryId != null) {
      final cid = activeCategoryId!;
      items = items.where((p) => _toInt(p['categoryId']) == cid).toList();
    }

    // Search filter
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((p) {
        final name = ((p['name'] ?? '').toString()).toLowerCase();
        final desc = ((p['description'] ?? '').toString()).toLowerCase();
        return name.contains(q) || desc.contains(q);
      }).toList();
    }

    // Availability filter
    if (_availableOnly) {
      items = items.where(_productAvailable).toList();
    }

    // Rating filter
    if (_minRating > 0) {
      items = items.where((p) => _productRating(p) >= _minRating).toList();
    }

    // Price filter
    if (_minPrice != null) {
      items = items
          .where((p) => ((p['price'] as num?)?.toDouble() ?? 0) >= _minPrice!)
          .toList();
    }
    if (_maxPrice != null) {
      items = items
          .where((p) => ((p['price'] as num?)?.toDouble() ?? 0) <= _maxPrice!)
          .toList();
    }

    // Offers-only filter: keep products that are in any active offer (product or category linked)
    if (_offersOnly) {
      final offerProd = <int>{};
      final offerCat = <int>{};
      for (final o in offers) {
        offerProd.addAll(_offerProductIds(o));
        offerCat.addAll(_offerCategoryIds(o));
      }
      items = items.where((p) {
        final pid = _toInt(p['id']);
        final cid = _toInt(p['categoryId']);
        return (pid > 0 && offerProd.contains(pid)) ||
            (cid > 0 && offerCat.contains(cid));
      }).toList();
    }

    // Sort
    items = _applySort(items);

    return items;
  }

  List<Map<String, dynamic>> _applySort(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return items;

    switch (_sortMode) {
      case _SortMode.newest:
        // Prefer createdAt if present; fallback to id.
        items.sort((a, b) {
          final adt = (a['createdAt'] ?? a['created_at'] ?? '').toString();
          final bdt = (b['createdAt'] ?? b['created_at'] ?? '').toString();
          if (adt.isNotEmpty && bdt.isNotEmpty) {
            return bdt.compareTo(adt);
          }
          final aid = (a['id'] as num?)?.toInt() ?? 0;
          final bid = (b['id'] as num?)?.toInt() ?? 0;
          return bid.compareTo(aid);
        });
        break;
      case _SortMode.popular:
        // Use the "popularProducts" list from API when available.
        final popularIds = <int, int>{};
        for (var i = 0; i < popular.length; i++) {
          final id = ((popular[i]['id'] as num?)?.toInt()) ?? 0;
          if (id > 0) popularIds[id] = i;
        }
        items.sort((a, b) {
          final aid = (a['id'] as num?)?.toInt() ?? 0;
          final bid = (b['id'] as num?)?.toInt() ?? 0;
          final ai = popularIds[aid];
          final bi = popularIds[bid];
          if (ai != null && bi != null) return ai.compareTo(bi);
          if (ai != null) return -1;
          if (bi != null) return 1;
          // fallback by rating
          return _productRating(b).compareTo(_productRating(a));
        });
        break;
      case _SortMode.topRated:
        items.sort((a, b) => _productRating(b).compareTo(_productRating(a)));
        break;
      case _SortMode.all:
        // Keep server order
        break;
    }
    return items;
  }

  List<Map<String, dynamic>> _filteredOffers() {
    var offs = offers.map((e) => Map<String, dynamic>.from(e)).toList();

    // Category chip filter: show only offers linked to the chosen category (or its products)
    if (activeCategoryId != null) {
      final cid = activeCategoryId!;
      offs = offs.where((o) {
        final cids = _offerCategoryIds(o);
        final pids = _offerProductIds(o);
        if (cids.isEmpty && pids.isEmpty) return true;
        if (cids.contains(cid)) return true;
        if (pids.isEmpty) return false;
        for (final p in _productsOfCategory(cid)) {
          final pid = _toInt(p['id']);
          if (pid > 0 && pids.contains(pid)) return true;
        }
        return false;
      }).toList();
    }

    // Search filter on offers
    final q = _q.trim().toLowerCase();
    if (q.isNotEmpty) {
      offs = offs.where((o) {
        final title = ((o['title'] ?? '').toString()).toLowerCase();
        final desc = ((o['description'] ?? '').toString()).toLowerCase();
        final code = ((o['code'] ?? '').toString()).toLowerCase();
        return title.contains(q) || desc.contains(q) || code.contains(q);
      }).toList();
    }

    return offs;
  }

  Future<void> _openFilters() async {
    double tmpMinRating = _minRating;
    bool tmpOffersOnly = _offersOnly;
    bool tmpAvailableOnly = _availableOnly;
    double? tmpMinPrice = _minPrice;
    double? tmpMaxPrice = _maxPrice;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return ListView(
                shrinkWrap: true,
                children: [
                  const Text('فلترة القائمة',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('عروض فقط'),
                    value: tmpOffersOnly,
                    onChanged: (v) => setModal(() => tmpOffersOnly = v),
                  ),
                  SwitchListTile(
                    title: const Text('متوفر فقط'),
                    value: tmpAvailableOnly,
                    onChanged: (v) => setModal(() => tmpAvailableOnly = v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'الحد الأدنى للتقييم: ${tmpMinRating.toStringAsFixed(1)}'),
                  Slider(
                    value: tmpMinRating,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    label: tmpMinRating.toStringAsFixed(1),
                    onChanged: (v) => setModal(() => tmpMinRating = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'أقل سعر',
                              border: OutlineInputBorder()),
                          onChanged: (v) =>
                              setModal(() => tmpMinPrice = double.tryParse(v)),
                          controller: TextEditingController(
                              text: tmpMinPrice?.toStringAsFixed(0) ?? ''),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'أعلى سعر',
                              border: OutlineInputBorder()),
                          onChanged: (v) =>
                              setModal(() => tmpMaxPrice = double.tryParse(v)),
                          controller: TextEditingController(
                              text: tmpMaxPrice?.toStringAsFixed(0) ?? ''),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _offersOnly = false;
                              _availableOnly = false;
                              _minPrice = null;
                              _maxPrice = null;
                              _minRating = 0;
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('مسح الفلاتر'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _offersOnly = tmpOffersOnly;
                              _availableOnly = tmpAvailableOnly;
                              _minPrice = tmpMinPrice;
                              _maxPrice = tmpMaxPrice;
                              _minRating = tmpMinRating;
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('تطبيق'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sortPillsRow() {
    Widget pill(String label, _SortMode mode) {
      final selected = _sortMode == mode;
      return InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => setState(() => _sortMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.secondary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final modes = [_SortMode.all, _SortMode.newest, _SortMode.popular, _SortMode.topRated];
    final labels = ['الجميع', 'انضم حديثاً', 'شائع', 'أعلى تصنيف'];
    return SizedBox(
      height: 48,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          reverse: false,
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => pill(labels[i], modes[i]),
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final json = await widget.api.getMenu();
      final cats = (json['categories'] is List)
          ? (json['categories'] as List)
          : <dynamic>[];
      final offs =
          (json['offers'] is List) ? (json['offers'] as List) : <dynamic>[];
      final pops = (json['popularProducts'] is List)
          ? (json['popularProducts'] as List)
          : <dynamic>[];

      categories =
          cats.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      offers = offs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      popular = pops.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // ===== Discounts badges (category + products) =====
      // UI-only enrichment: compute a "خصم X%" badge for categories based on the
      // highest discount among their products. Also ensure products expose
      // a discountBadge if they have originalPrice/price.
      for (final c in categories) {
        final ps =
            (c['products'] is List) ? (c['products'] as List) : <dynamic>[];
        int maxPct = 0;
        for (final pAny in ps) {
          if (pAny is! Map) continue;
          final price = (pAny['price'] as num?)?.toDouble() ?? 0;
          final orig = (pAny['originalPrice'] as num?)?.toDouble();
          int pct = 0;
          if (orig != null && orig > 0 && orig > price) {
            pct = (((orig - price) / orig) * 100).round();
          }
          // Backward compatible: if backend already provides percent/badge, keep it.
          final existingBadge = (pAny['discountBadge'] ?? '').toString().trim();
          if (existingBadge.isEmpty && pct > 0) {
            pAny['discountBadge'] = 'خصم $pct%';
          }
          if (pct > maxPct) maxPct = pct;
        }

        final existingCatBadge =
            (c['discountBadge'] ?? c['categoryDiscountBadge'] ?? '')
                .toString()
                .trim();
        if (existingCatBadge.isEmpty && maxPct > 0) {
          c['discountBadge'] = 'خصم $maxPct%';
        }
      }

      // Popular cards may come without badge; enrich similarly.
      for (final p in popular) {
        final price = (p['price'] as num?)?.toDouble() ?? 0;
        final orig = (p['originalPrice'] as num?)?.toDouble();
        if ((p['discountBadge'] ?? '').toString().trim().isEmpty &&
            orig != null &&
            orig > 0 &&
            orig > price) {
          final pct = (((orig - price) / orig) * 100).round();
          if (pct > 0) p['discountBadge'] = 'خصم $pct%';
        }
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic>? _categoryById(int id) {
    for (final c in categories) {
      if (_toInt(c['id']) == id) return c;
    }
    return null;
  }

  List<Map<String, dynamic>> _productsOfCategory(int categoryId) {
    final c = _categoryById(categoryId);
    if (c == null) return const [];
    final products =
        (c['products'] is List) ? (c['products'] as List) : <dynamic>[];
    return products.map((p) => Map<String, dynamic>.from(p as Map)).toList();
  }

  String _imgOfProduct(Map<String, dynamic> p) {
    // Prefer primary image; otherwise first image; otherwise empty.
    final images = (p['images'] is List) ? (p['images'] as List) : <dynamic>[];
    if (images.isEmpty) return '';
    final list =
        images.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.sort((a, b) {
      final ap = (a['isPrimary'] == true) ? 0 : 1;
      final bp = (b['isPrimary'] == true) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      return ((a['sortOrder'] as int?) ?? 0)
          .compareTo(((b['sortOrder'] as int?) ?? 0));
    });
    return (list.first['url'] ?? '').toString();
  }

  String _imgOfCategory(Map<String, dynamic> c) =>
      (c['imageUrl'] ?? '').toString();

  String _absUrl(String u) {
    final url = u.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${widget.api.baseUrl}$url';
    return '${widget.api.baseUrl}/$url';
  }

  Map<String, dynamic>? _findFullProductById(int id) {
    for (final c in categories) {
      final ps = (c['products'] is List) ? (c['products'] as List) : const [];
      for (final p in ps) {
        final pm = Map<String, dynamic>.from(p as Map);
        if (_toInt(pm['id']) == id) return pm;
      }
    }
    return null;
  }

  bool _hasOptions(Map<String, dynamic> p) {
    final v = (p['variants'] is List) ? (p['variants'] as List) : const [];
    final a = (p['addons'] is List) ? (p['addons'] as List) : const [];
    return v.isNotEmpty || a.isNotEmpty;
  }

  int _basicQtyInCart(int productId) {
    // Basic snapshot is what addToCartBasic uses.
    const snap = '{"variantId":null,"addonIds":[],"note":null}';
    final key = '$productId|$snap';
    for (final it in widget.state.cart) {
      if (it.key == key) return it.qty;
    }
    return 0;
  }

  void _quickAdd(Map<String, dynamic> p) {
    // If the item has options, we must open details so user can choose.
    if (_hasOptions(p)) {
      final categoryId =
          _toInt(p['categoryId']) ?? 0; // ignore: dead_null_aware_expression
      final catName = (_categoryById(categoryId)?['name'] ?? '').toString();
      _openProduct(p, categoryName: catName);
      return;
    }
    widget.state.addToCartBasic(
      productId: (p['id'] as int),
      name: (p['name'] ?? '').toString(),
      basePrice: (p['price'] as num).toDouble(),
    );
  }

  void _openCart() {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => CartScreen(api: widget.api, state: widget.state)),
    );
  }

  Widget _withCartButton(Widget child) {
    // IMPORTANT: Keep the cart feature and cart screen (bottom navigation),
    // but remove the floating cart button that appears in the corner.
    return child;
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _mw(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: child,
      ),
    );
  }

  IconData _categoryIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('برجر')) return Icons.lunch_dining;
    if (n.contains('بيتزا')) return Icons.local_pizza;
    if (n.contains('ساند')) return Icons.fastfood;
    if (n.contains('حل')) return Icons.icecream;
    if (n.contains('مشر')) return Icons.local_drink;
    if (n.contains('مقبل')) return Icons.restaurant;
    return Icons.restaurant_menu;
  }

  Widget _searchBar() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: TextField(
        controller: _searchCtl,
        textDirection: TextDirection.rtl,
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: 'ابحث في القائمة...',
          hintStyle: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search_rounded,
              color: theme.colorScheme.primary, size: 24),
          suffixIcon: _isSearching
              ? IconButton(
                  tooltip: 'مسح',
                  onPressed: () => _searchCtl.clear(),
                  icon: Icon(Icons.close_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: theme.colorScheme.outline.withOpacity(0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: theme.colorScheme.outline.withOpacity(0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: theme.colorScheme.primary, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _badge(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _imgCard(String url, {double? height, BorderRadius? radius}) {
    final r = radius ?? BorderRadius.circular(16);
    final surfaceDim = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (url.trim().isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: surfaceDim,
          borderRadius: r,
        ),
        child: Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final w = MediaQuery.sizeOf(context).width;
    final cacheW = (w * dpr).round().clamp(1, 2048);
    final cacheH = height != null ? (height! * dpr).round().clamp(1, 2048) : cacheW;
    return ClipRRect(
      borderRadius: r,
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        cacheWidth: cacheW,
        cacheHeight: cacheH,
        errorBuilder: (_, __, ___) => Container(
          height: height,
          decoration: BoxDecoration(color: surfaceDim, borderRadius: r),
          child: Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  void _openProduct(Map<String, dynamic> p, {required String categoryName}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(
          api: widget.api,
          state: widget.state,
          product: p,
          categoryName: categoryName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'جاري تحميل القائمة...',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'تعذر تحميل القائمة\n$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredOffers = _filteredOffers();
    final filteredProducts = _filteredProducts();

    // ===== صف الفئات (الكل - بيتزا - عربي...) — صف واحد قابل للسحب مثل العروض =====
    final categoryCards = [
      UiCategoryCard(
        key: ValueKey('cat_all'),
        title: 'الكل',
        imageUrl: '',
        icon: Icons.apps,
        selected: activeCategoryId == null,
        onTap: () => setState(() => activeCategoryId = null),
      ),
      ...categories.map((c) => UiCategoryCard(
        key: ValueKey('cat_${_toInt(c['id'])}'),
        title: (c['name'] ?? '').toString(),
        imageUrl: _absUrl((c['imageUrl'] ?? c['iconUrl'] ?? '').toString()),
        icon: Icons.restaurant_menu,
        selected: activeCategoryId == _toInt(c['id']),
        badgeText: null,
        onTap: () => setState(() => activeCategoryId = _toInt(c['id'])),
      )),
    ];
    // RTL: الكل أقصى اليمين، الفئات الجديدة تظهر على يسارها (بدون reverse)
    Widget categoriesRow = Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        height: 118,
        child: ListView.separated(
          padding: EdgeInsets.zero,
          scrollDirection: Axis.horizontal,
          reverse: false,
          itemCount: categoryCards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => categoryCards[i],
        ),
      ),
    );

    return _withCartButton(RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          // البحث في الأعلى
          SliverToBoxAdapter(child: _mw(_searchBar())),

          // البنرات بعد البحث
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _HomeBannerCarousel(urls: widget.state.homeBanners),
            ),
          ),

          // Category bubbles
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: categoriesRow,
            ),
          ),

          // Offers section - استخدام SliverToBoxAdapter بدلاً من SliverPersistentHeader لتجنب overflow
          SliverToBoxAdapter(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _sectionTitle(
                      activeCategoryId == null
                          ? 'العروض والخصومات'
                          : 'عروض الفئة المختارة',
                      trailing: filteredOffers.isEmpty
                          ? null
                          : _badge('${filteredOffers.length}'),
                    ),
                    const SizedBox(height: 6),
                    if (filteredOffers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 20),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            activeCategoryId == null
                                ? 'لا توجد عروض حالياً'
                                : 'لا توجد عروض لهذه الفئة',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          scrollDirection: Axis.horizontal,
                          itemCount: filteredOffers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            final o = filteredOffers[i];
                            final images = (o['images'] is List)
                                ? (o['images'] as List)
                                : const [];
                            final raw = images.isNotEmpty
                                ? (((images.first as Map)['url'] ?? '')
                                    .toString())
                                : (o['imageUrl'] ?? '').toString();
                            final img = _absUrl(raw);
                            final pb = (o['priceBefore'] as num?)?.toDouble();
                            final pa = (o['priceAfter'] as num?)?.toDouble();
                            return SizedBox(
                              width: 180,
                              child: UiOfferCard(
                                title: (o['title'] ?? '').toString(),
                                description: (o['description'] ?? '').toString(),
                                imageUrl: img,
                                priceAfter: pa,
                                priceBefore: pb,
                                onAdd: () => _quickAddOffer(
                                    Map<String, dynamic>.from(o as Map)),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => OfferDetailsScreen(
                                          api: widget.api,
                                          state: widget.state,
                                          offer: o)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

// Products
          SliverToBoxAdapter(
            child: _sectionTitle(
              activeCategoryId == null
                  ? 'جميع الأصناف'
                  : 'أصناف ${_categoryById(activeCategoryId!)?['name'] ?? "الفئة المختارة"}',
              trailing: _badge('${filteredProducts.length}'),
            ),
          ),

          // Sort & filters pills (under products section)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: _sortPillsRow(),
            ),
          ),

          if (filteredProducts.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                child: Text(
                  activeCategoryId == null
                      ? 'لا توجد أصناف متاحة'
                      : 'لا توجد أصناف في هذه الفئة',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.right,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                // Make product cards match the offer card sizing on wide screens (web) by
                // limiting the max tile width. This prevents huge cards when running on Chrome.
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Offer card ~320x240 => 1.33. Keep products close to that.
                  childAspectRatio: 1.32,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final p = filteredProducts[i];
                    final categoryId = (p['categoryId'] as num?)?.toInt() ?? 0;
                    final catName =
                        (_categoryById(categoryId)?['name'] ?? '').toString();
                    final pid = (p['id'] as num?)?.toInt() ?? 0;
                    final qty = widget.state.cart
                        .where((c) => c.productId == pid)
                        .fold<int>(0, (s, x) => s + x.qty);

                    return UiProductGridCard(
                      name: (p['name'] ?? '').toString(),
                      description: (p['description'] ?? '').toString(),
                      imageUrl: _absUrl(_firstImageRaw(p)),
                      price: (p['price'] as num?)?.toDouble() ?? 0,
                      originalPrice: (p['originalPrice'] as num?)?.toDouble(),
                      discountBadge: (p['discountBadge'] ?? '').toString(),
                      qtyInCart: qty,
                      rating:
                          (_productRating(p) > 0 ? _productRating(p) : null),
                      isAvailable: (p['isAvailable'] ?? true) == true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailsScreen(
                            api: widget.api,
                            state: widget.state,
                            product: p,
                            categoryName: catName,
                          ),
                        ),
                      ),
                      onAdd: () => widget.state.addToCartBasic(
                        productId: pid,
                        name: (p['name'] ?? '').toString(),
                        basePrice: (p['price'] as num?)?.toDouble() ?? 0,
                      ),
                    );
                  },
                  childCount: filteredProducts.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    ));
  }
}

/// Simple pinned header delegate used to keep the offers section visible while scrolling.
/// Market-ready top banner carousel (admin-managed from Settings).
/// Uses only core Flutter widgets (no extra packages).
class _HomeBannerCarousel extends StatefulWidget {
  const _HomeBannerCarousel({required this.urls});
  final List<String>? urls;

  @override
  State<_HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<_HomeBannerCarousel> {
  final PageController _pc = PageController();
  Timer? _timer;
  int _index = 0;

  List<String> get _urls =>
      (widget.urls ?? const []).where((e) => e.trim().isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.urls?.length ?? 0) != (widget.urls?.length ?? 0)) {
      _index = 0;
      _pc.jumpToPage(0);
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    final u = _urls;
    if (u.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_index + 1) % u.length;
      _pc.animateToPage(next,
          duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = _urls;
    if (u.isEmpty) return const SizedBox.shrink();
    final r = BorderRadius.circular(20);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: r,
          child: SizedBox(
            height: 170,
            child: PageView.builder(
              controller: _pc,
              itemCount: u.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final url = u[i];
                final dpr = MediaQuery.of(context).devicePixelRatio;
                final w = MediaQuery.sizeOf(context).width;
                final cacheW = (w * dpr).round().clamp(1, 2048);
                final cacheH = (170.0 * dpr).round().clamp(1, 2048);
                return Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  filterQuality: FilterQuality.high,
                  cacheWidth: cacheW,
                  cacheHeight: cacheH,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (u.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(u.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 7,
                width: active ? 18 : 7,
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          ),
      ],
    );
  }
}
