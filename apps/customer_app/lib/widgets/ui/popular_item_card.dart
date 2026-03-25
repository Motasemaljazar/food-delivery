import 'package:flutter/material.dart';

class UiPopularItemCard extends StatelessWidget {
  const UiPopularItemCard({
    super.key,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.price,
    required this.onTap,
    required this.onAdd,
  });

  final String name;
  final String description;
  final String imageUrl;
  final double price;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 190,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.04)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: imageUrl.trim().isEmpty
                    ? Container(color: Colors.black12, child: const Center(child: Icon(Icons.image_outlined)))
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: Colors.black12, child: const Center(child: Icon(Icons.broken_image_outlined))),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, height: 1.2)),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(child: Text('${price.toStringAsFixed(0)} ل.س', style: const TextStyle(fontWeight: FontWeight.w900))),
                SizedBox(
                  height: 40,
                  width: 40,
                  child: FilledButton(
                    onPressed: onAdd,
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: const Icon(Icons.add, size: 20),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
