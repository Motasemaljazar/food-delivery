import 'package:flutter/material.dart';

import 'discount_corner_badge.dart';

/// بطاقة عرض محسنة - تم إصلاح مشكلة الـ overflow نهائياً
class UiOfferCard extends StatelessWidget {
  const UiOfferCard({
    super.key,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.priceAfter,
    required this.priceBefore,
    required this.onTap,
    this.onAdd,
  });

  final String title;
  final String description;
  final String imageUrl;
  final double? priceAfter;
  final double? priceBefore;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disc = (priceBefore != null && priceAfter != null && priceBefore! > 0)
        ? (((priceBefore! - priceAfter!) / priceBefore!) * 100).round()
        : null;

    // بطاقة عرض مدمجة — عرضان بجانب بعض، فراغات أقل
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.04)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // صورة العرض — نسبة 4/3 مدمجة
            Expanded(
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: imageUrl.trim().isEmpty
                              ? Container(
                                  color: Colors.black12,
                                  child: const Center(child: Icon(Icons.local_offer_outlined, size: 28)),
                                )
                              : Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                  cacheWidth: 800,
                                  cacheHeight: 600,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.black12,
                                    child: const Center(child: Icon(Icons.broken_image_outlined, size: 28)),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (disc != null)
                      UiDiscountCornerBadge(text: 'خصم $disc%', top: 6, right: 6),
                    if (onAdd != null)
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          height: 32,
                          width: 32,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onAdd,
                              borderRadius: BorderRadius.circular(10),
                              child: const Center(child: Icon(Icons.add, size: 18, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                    ),
                  ],
                  if (priceAfter != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${priceAfter!.toStringAsFixed(0)} ل.س',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                        if (priceBefore != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            priceBefore!.toStringAsFixed(0),
                            style: TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
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
