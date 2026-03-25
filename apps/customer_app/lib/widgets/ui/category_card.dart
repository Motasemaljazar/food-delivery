import 'package:flutter/material.dart';

class UiCategoryCard extends StatelessWidget {
  const UiCategoryCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.icon,
    this.selected = false,
    this.badgeText,
    required this.onTap,
  });

  final String title;
  final String imageUrl;
  final IconData icon;
  final bool selected;
  final String? badgeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bt = (badgeText ?? '').trim();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(0.08) : cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: selected ? cs.primary.withOpacity(0.35) : Colors.black.withOpacity(0.04), width: selected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl.trim().isEmpty
                  ? Icon(icon, color: cs.primary)
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      cacheWidth: 156,
                      cacheHeight: 156,
                      errorBuilder: (_, __, ___) => Icon(icon, color: cs.primary),
                    ),
                ),
                // Corner discount badge
                if (bt.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE53935),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          topRight: Radius.circular(14),
                        ),
                      ),
                      child: Text(
                        bt,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, height: 1),
                      ),
                    ),
                  )

              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
