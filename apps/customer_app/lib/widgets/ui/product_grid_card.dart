import 'package:flutter/material.dart';

/// Card used to render products in a grid (market-ready, like offers).
class UiProductGridCard extends StatelessWidget {
  const UiProductGridCard({
    super.key,
    required this.name,
    this.description,
    required this.imageUrl,
    required this.price,
    this.originalPrice,
    this.discountBadge = '',
    this.rating,
    this.qtyInCart = 0,
    this.isAvailable = true,
    required this.onTap,
    required this.onAdd,
  });

  final String name;
  /// Optional description (kept for compatibility with existing callers).
  /// We don't render it in the grid to keep cards compact/market-ready.
  final String? description;
  final String imageUrl;
  final double price;
  final double? originalPrice;
  final String discountBadge;
  final double? rating;
  final int qtyInCart;
  final bool isAvailable;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final showBadge = discountBadge.trim().isNotEmpty;
    final hasStrike = originalPrice != null && originalPrice! > price;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withOpacity(0.08),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: cs.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // صورة المنتج
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                      child: imageUrl.trim().isEmpty
                          ? Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    cs.primary.withOpacity(0.1),
                                    cs.secondary.withOpacity(0.1),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Icon(Icons.restaurant_menu, size: 48, color: cs.onSurfaceVariant.withOpacity(0.5)),
                              ),
                            )
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                              cacheWidth: 1200,
                              cacheHeight: 1200,
                              errorBuilder: (_, __, ___) => Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      cs.primary.withOpacity(0.1),
                                      cs.secondary.withOpacity(0.1),
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined, size: 48, color: cs.onSurfaceVariant.withOpacity(0.5)),
                                ),
                              ),
                            ),
                    ),
                  ),
                  
                  // شارة الخصم
                  if (showBadge)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE53935), Color(0xFFD32F2F)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE53935).withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          discountBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  
                  // أيقونة "غير متاح"
                  if (!isAvailable)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.scrim.withOpacity(0.5),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.block,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // معلومات المنتج
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // اسم المنتج والتقييم — الاسم من اليمين (RTL)
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (rating != null) ...[
                          const SizedBox(width: 8),
                          Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.secondary.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, size: 14, color: cs.secondary),
                              const SizedBox(width: 2),
                              Text(
                                rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  ),
                  const SizedBox(height: 12),
                  
                  
                  // السعر من اليمين وزر الإضافة من اليسار (RTL)
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Row(
                      children: [
                        // الأسعار (تظهر على اليمين في RTL)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (hasStrike)
                              Text(
                                '${originalPrice!.toStringAsFixed(0)} ل.س',
                                style: TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            Text(
                              '${price.toStringAsFixed(0)} ل.س',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // زر الإضافة (يظهر على اليسار في RTL)
                        Container(
                          height: 40,
                          width: 40,
                          decoration: BoxDecoration(
                            color: isAvailable ? cs.primary : cs.onSurfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: isAvailable
                                ? [
                                    BoxShadow(
                                      color: cs.primary.withOpacity(0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: isAvailable ? onAdd : null,
                              borderRadius: BorderRadius.circular(14),
                              child: const Icon(
                                Icons.add,
                                size: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // مؤشر الكمية في السلة
                  if (qtyInCart > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: cs.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'في السلة: $qtyInCart',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.shopping_cart,
                            size: 12,
                            color: cs.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  // حالة عدم التوفر
                  if (!isAvailable) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'غير متاح حالياً',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
