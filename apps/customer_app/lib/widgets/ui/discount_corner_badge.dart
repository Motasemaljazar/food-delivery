import 'package:flutter/material.dart';

/// Small, market-style discount badge that sits in the top-right corner.
/// Used for categories, products and offers.
class UiDiscountCornerBadge extends StatelessWidget {
  const UiDiscountCornerBadge({
    super.key,
    required this.text,
    this.top = 8,
    this.right = 8,
  });

  final String text;
  final double top;
  final double right;

  @override
  Widget build(BuildContext context) {
    final t = text.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    final yellow = Theme.of(context).colorScheme.secondary;

    return Positioned(
      top: top,
      right: right,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: yellow,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            height: 1,
          ),
        ),
      ),
    );
  }
}
