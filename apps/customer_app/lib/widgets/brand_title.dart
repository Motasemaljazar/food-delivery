import 'package:flutter/material.dart';
import '../models/app_state.dart';

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, required this.state, this.suffix, this.logoSize = 40});
  final AppState state;
  final String? suffix;
  /// حجم اللوغو في الشريط العلوي (افتراضي 40 للواجهة الرئيسية)
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (state.restaurantName).trim();
    final displayName = name.isEmpty ? 'توب شيف' : name;
    final logo = (state.logoUrl ?? '').trim();
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.secondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      textDirection: TextDirection.rtl,
      children: [
        // اللوغو أولاً في RTL فيظهر بأقصى اليمين ثم النص (لمسة أصفر من ألوان اللوغو)
        Container(
          width: logoSize + 8,
          height: logoSize + 8,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: secondary.withOpacity(0.35), width: 1),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: secondary.withOpacity(0.12),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: logo.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    logo,
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(Icons.restaurant_rounded, size: logoSize * 0.6, color: primary),
                  ),
                )
              : Icon(Icons.restaurant_rounded, size: logoSize * 0.6, color: primary),
        ),
        SizedBox(width: logoSize * 0.3),
        Flexible(
          child: Text(
            suffix == null || suffix!.trim().isEmpty
                ? displayName
                : '$displayName — ${suffix!.trim()}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.appBarTheme.foregroundColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
