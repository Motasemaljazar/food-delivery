import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import 'product_details_screen.dart';

String _absUrl(String baseUrl, String? url) {
  if (url == null || url.trim().isEmpty) return '';
  final u = url.trim();
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final b = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  final p = u.startsWith('/') ? u : '/$u';
  return '$b$p';
}

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
  List<dynamic> categories = [];
  List<dynamic> offers = [];
  String query = '';
  int? activeCategoryId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState((){loading=true; error=null;});
    try {
      final json = await widget.api.getMenu();
      categories = (json['categories'] as List<dynamic>)
          .map((c)=>c as Map<String, dynamic>)
          .toList();
      offers = (json['offers'] is List) ? (json['offers'] as List<dynamic>) : <dynamic>[];
    } catch (e) {
      error = e.toString();
    } finally {
      if(mounted) setState(()=>loading=false);
    }
  }

  List<Map<String, dynamic>> _filteredProductsForCategory(Map<String, dynamic> c) {
    final products = (c['products'] as List<dynamic>).map((p) => p as Map<String, dynamic>).toList();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return products;
    return products.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final desc = (p['description'] ?? '').toString().toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();
  }

  Widget _sectionTitle(BuildContext context, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _image(String url, {double? height}) {
    if (url.trim().isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
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

  Map<String, dynamic>? _bestOfferFor({required int productId, required int categoryId}) {
    Map<String, dynamic>? best;
    double bestValue = 0.0;
    for (final raw in offers) {
      final o = raw as Map<String, dynamic>;
      final type = o['type']?.toString();
      if (type == 'Product' && (o['productId'] == productId)) {
        // Keep type as double (avoid `num` inference from the ternary)
        final v = (o['value'] is num) ? (o['value'] as num).toDouble() : 0.0;
        if (v > bestValue) { best = o; bestValue = v; }
      }
      if (type == 'Category' && (o['categoryId'] == categoryId)) {
        // Keep type as double (avoid `num` inference from the ternary)
        final v = (o['value'] is num) ? (o['value'] as num).toDouble() : 0.0;
        if (v > bestValue) { best = o; bestValue = v; }
      }
    }
    return best;
  }

  Widget _discountBadge(BuildContext context, Map<String, dynamic>? offer) {
    if (offer == null) return const SizedBox.shrink();
    final discountType = offer['discountType']?.toString();
    final val = (offer['value'] is num) ? (offer['value'] as num).toDouble() : 0.0;
    final label = (discountType == 'Percent') ? '%${val.toStringAsFixed(0)}' : '-${val.toStringAsFixed(0)}';
    return PositionedDirectional(
      top: 10,
      start: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(blurRadius: 10, color: Color(0x22000000), offset: Offset(0, 4))],
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _productCard(BuildContext context, Map<String, dynamic> p, {required int categoryId}) {
    final price = (p['price'] as num).toDouble();
    final imagesRaw = (p['images'] is Iterable) ? (p['images'] as Iterable).map((e) => e?.toString() ?? '').toList() : <String>[];
    final baseUrl = widget.api.baseUrl;
    final images = imagesRaw.map((u) => _absUrl(baseUrl, u)).where((u) => u.isNotEmpty).toList();

    final offer = _bestOfferFor(productId: p['id'] as int, categoryId: categoryId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(
              api: widget.api,
              state: widget.state,
              product: p,
              categoryId: categoryId,
              offer: offer,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 170,
              child: Stack(
                children: [
                  if (images.isNotEmpty)
                    PageView.builder(
                      itemCount: images.length,
                      itemBuilder: (context, i) => _image(images[i], height: 170),
                    )
                  else
                    _image('', height: 170),
                  _discountBadge(context, offer),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p['name'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${price.toStringAsFixed(0)} ل.س',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            if ((p['description'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                (p['description'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add_shopping_cart),
                    onPressed: () => widget.state.addToCartBasic(
                      productId: p['id'] as int,
                      name: p['name'] as String,
                      basePrice: price,
                    ),
                    label: const Text('أضف سريعاً'),
                  ),
                ),
              ],
            )
          ],
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if(loading) return const Center(child: CircularProgressIndicator());
    if(error!=null) return Center(child: Text(error!));

    final visibleCategories = activeCategoryId == null
        ? categories
        : categories.where((c) => (c as Map<String, dynamic>)['id'] == activeCategoryId).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث عن صنف…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true,
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: FilterChip(
                            selected: activeCategoryId == null,
                            label: const Text('الكل'),
                            onSelected: (_) => setState(() => activeCategoryId = null),
                          ),
                        ),
                        ...categories.map((c) {
                          final cm = c as Map<String, dynamic>;
                          final selected = activeCategoryId == (cm['id'] as int);
                          return Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: FilterChip(
                              selected: selected,
                              label: Text(cm['name'].toString()),
                              onSelected: (_) => setState(() => activeCategoryId = selected ? null : (cm['id'] as int)),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (offers.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(context, 'العروض الحالية'),
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, i) {
                        final o = offers[i] as Map<String, dynamic>;
                        return Container(
                          width: 280,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [
                                Theme.of(context).colorScheme.primaryContainer,
                                Theme.of(context).colorScheme.secondaryContainer,
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(o['title']?.toString() ?? 'عرض', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Text(
                                  (o['description'] ?? '').toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemCount: offers.length,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),

          if (query.trim().isNotEmpty)
            SliverToBoxAdapter(child: _sectionTitle(context, 'نتائج البحث')),

          // Products list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final c = visibleCategories[i] as Map<String, dynamic>;
                final products = _filteredProductsForCategory(c);
                if (products.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline),
                            const SizedBox(width: 10),
                            Expanded(child: Text('لا توجد نتائج ضمن قسم "${c['name']}".')),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (activeCategoryId == null && query.trim().isEmpty)
                      _sectionTitle(context, c['name'].toString()),
                    ...products.map((p) => _productCard(context, p, categoryId: c['id'] as int)),
                  ],
                );
              },
              childCount: visibleCategories.length,
            ),
          ),

          // If categories empty
          if (categories.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.restaurant_menu, size: 48),
                    const SizedBox(height: 10),
                    Text('لا توجد أصناف بعد', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('لا توجد أصناف متاحة حالياً. يمكنك التواصل مع المطعم من تبويب الدعم.'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
