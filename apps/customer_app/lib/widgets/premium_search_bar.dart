import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PremiumSearchBar extends StatefulWidget {
  const PremiumSearchBar({
    super.key,
    required this.controller,
    this.hint = 'ابحث عن منتج...',
    this.onChanged,
    this.onSubmitted,
    this.onFilterTap,
    this.hasActiveFilters = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onFilterTap;
  final bool hasActiveFilters;

  @override
  State<PremiumSearchBar> createState() => _PremiumSearchBarState();
}

class _PremiumSearchBarState extends State<PremiumSearchBar>
    with SingleTickerProviderStateMixin {
  late FocusNode _focusNode;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
      if (_isFocused) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: _isFocused
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.2),
            width: _isFocused ? 2 : 1,
          ),
          boxShadow: _isFocused 
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.2),
                    offset: const Offset(0, 4),
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                ]
              : AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            // Search Icon
            Padding(
              padding: const EdgeInsets.only(
                right: AppTheme.spaceM,
                left: AppTheme.spaceS,
              ),
              child: Icon(
                Icons.search_rounded,
                color: _isFocused 
                    ? colorScheme.primary 
                    : colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            
            // Text Field
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                style: theme.textTheme.bodyMedium,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spaceM,
                  ),
                ),
              ),
            ),
            
            // Clear Button
            if (widget.controller.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: AppTheme.spaceS),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      widget.controller.clear();
                      widget.onChanged?.call('');
                    },
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceS),
                      child: Icon(
                        Icons.clear_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            
            // Filter Button
            if (widget.onFilterTap != null)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppTheme.spaceS,
                  right: AppTheme.spaceS,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onFilterTap,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: Container(
                      padding: const EdgeInsets.all(AppTheme.spaceS),
                      decoration: BoxDecoration(
                        color: widget.hasActiveFilters
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: widget.hasActiveFilters
                                ? Colors.white
                                : colorScheme.onSurfaceVariant,
                          ),
                          
                          // Active Filters Indicator
                          if (widget.hasActiveFilters)
                            Positioned(
                              top: -4,
                              left: -4,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppTheme.errorColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
