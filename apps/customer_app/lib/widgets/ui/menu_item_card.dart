import 'package:flutter/material.dart';

class UiMenuItemCard extends StatelessWidget {
  const UiMenuItemCard({
    super.key,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.price,
    this.originalPrice,
    this.discountBadge = '',
    this.qtyInCart = 0,
    this.rating,
    this.isAvailable = true,
    required this.onTap,
    required this.onAdd,
  });

  final String name;
  final String description;
  final String imageUrl;
  final double price;
  final double? originalPrice;
  final String discountBadge;
  final int qtyInCart;
  final double? rating;
  final bool isAvailable;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showBadge = discountBadge.trim().isNotEmpty;
    final hasStrike = originalPrice != null && originalPrice! > price;
    final canAdd = isAvailable;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.04)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 92,
                height: 78,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageUrl.trim().isEmpty
                        ? Container(color: Colors.black12, child: const Center(child: Icon(Icons.image_outlined)))
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black12,
                              child: const Center(child: Icon(Icons.broken_image_outlined)),
                            ),
                          ),
                    // Corner discount badge on the item image
                    if (showBadge)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53935),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(14),
                              topRight: Radius.circular(18),
                            ),
                          ),
                          child: Text(
                            discountBadge,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, height: 1),
                          ),
                        ),
                      )
,
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                      if (rating != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.star_rounded, size: 16, color: Theme.of(context).colorScheme.secondary),
                        const SizedBox(width: 2),
                        Text(rating!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      ]
                    ],
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, height: 1.2)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${price.toStringAsFixed(0)} ل.س', style: const TextStyle(fontWeight: FontWeight.w900)),
                      if (hasStrike) const SizedBox(width: 8),
                      if (hasStrike)
                        Text(
                          originalPrice!.toStringAsFixed(0),
                          style: TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                        ),
                      // Discount badge is now shown as a circular badge on the image.
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 40,
                  width: 40,
                  child: FilledButton(
                    onPressed: canAdd ? onAdd : null,
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Icon(Icons.add, size: 20),
                  ),
                ),
                if (qtyInCart > 0) ...[
                  const SizedBox(height: 6),
                  Text('x$qtyInCart', style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
                if (!canAdd) ...[
                  const SizedBox(height: 6),
                  Text('غير متاح', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w800, fontSize: 11)),
                ]
              ],
            )
          ],
        ),
      ),
    );
  }
}
