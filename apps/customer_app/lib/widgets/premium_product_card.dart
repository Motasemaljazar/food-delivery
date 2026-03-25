import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class PremiumProductCard extends StatefulWidget {
  const PremiumProductCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.description,
    required this.price,
    this.originalPrice,
    this.rating,
    this.reviewCount,
    this.badge,
    this.onTap,
    this.onAddToCart,
    this.isAvailable = true,
  });

  final String imageUrl;
  final String title;
  final String description;
  final double price;
  final double? originalPrice;
  final double? rating;
  final int? reviewCount;
  final String? badge; // "جديد", "الأكثر مبيعاً", "عرض خاص"
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;
  final bool isAvailable;

  @override
  State<PremiumProductCard> createState() => _PremiumProductCardState();
}

class _PremiumProductCardState extends State<PremiumProductCard> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasDiscount = widget.originalPrice != null && 
        widget.originalPrice! > widget.price;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isAvailable 
                ? AppTheme.cardBg 
                : AppTheme.cardBg.withOpacity(0.6),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            boxShadow: _isPressed ? [] : AppTheme.cardShadow,
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section with Badge
              Stack(
                children: [
                  // Product Image
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.radiusLarge),
                    ),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: widget.imageUrl.isNotEmpty
                          ? Image.network(
                              widget.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildPlaceholder(),
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return _buildPlaceholder();
                              },
                            )
                          : _buildPlaceholder(),
                    ),
                  ),
                  
                  // Unavailable Overlay
                  if (!widget.isAvailable)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTheme.radiusLarge),
                        ),
                        child: Container(
                          color: Colors.black.withOpacity(0.5),
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spaceM,
                              vertical: AppTheme.spaceS,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                            ),
                            child: Text(
                              'غير متوفر',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppTheme.errorColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  
                  // Badge (New, Best Seller, etc.)
                  if (widget.badge != null && widget.isAvailable)
                    Positioned(
                      top: AppTheme.spaceS,
                      right: AppTheme.spaceS,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spaceM,
                          vertical: AppTheme.spaceS,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          boxShadow: AppTheme.buttonShadow,
                        ),
                        child: Text(
                          widget.badge!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  
                  // Discount Badge
                  if (hasDiscount && widget.isAvailable)
                    Positioned(
                      top: AppTheme.spaceS,
                      left: AppTheme.spaceS,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spaceS,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: Text(
                          '-${(((widget.originalPrice! - widget.price) / widget.originalPrice!) * 100).toInt()}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              
              // Content Section
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spaceM),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 4),
                      
                      // Description
                      if (widget.description.isNotEmpty)
                        Text(
                          widget.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      
                      const Spacer(),
                      
                      // Rating
                      if (widget.rating != null && widget.rating! > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.spaceS),
                          child: Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: AppTheme.accentColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.rating!.toStringAsFixed(1),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.reviewCount != null && widget.reviewCount! > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(${widget.reviewCount})',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      
                      // Price Section
                      Row(
                        children: [
                          // Current Price
                          Text(
                            '${widget.price.toStringAsFixed(2)} ر.س',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          
                          const SizedBox(width: AppTheme.spaceS),
                          
                          // Original Price (if discounted)
                          if (hasDiscount)
                            Text(
                              '${widget.originalPrice!.toStringAsFixed(2)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          
                          const Spacer(),
                          
                          // Add to Cart Button
                          if (widget.onAddToCart != null && widget.isAvailable)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: widget.onAddToCart,
                                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                child: Container(
                                  padding: const EdgeInsets.all(AppTheme.spaceS),
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.primaryGradient,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                    boxShadow: AppTheme.buttonShadow,
                                  ),
                                  child: const Icon(
                                    Icons.add_shopping_cart_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.restaurant_menu_rounded,
        size: 48,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
      ),
    );
  }
}
