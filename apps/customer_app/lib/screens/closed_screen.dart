import 'package:flutter/material.dart';
import '../models/app_state.dart';

class ClosedScreen extends StatefulWidget {
  const ClosedScreen({super.key, required this.state, this.onRefresh});
  final AppState state;
  final Future<bool> Function()? onRefresh;

  @override
  State<ClosedScreen> createState() => _ClosedScreenState();
}

class _ClosedScreenState extends State<ClosedScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = (widget.state.closedScreenImageUrl ?? '').trim();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = 0.4 + (_c.value * 0.35);
          return Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.2,
                colors: [
                  Colors.black.withOpacity(0.10),
                  Colors.black.withOpacity(0.55),
                ],
                stops: [t, 1.0],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (img.isNotEmpty)
                  Opacity(
                    opacity: 0.85,
                    child: Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                Container(color: Colors.black.withOpacity(0.45)),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScaleTransition(
                          scale: Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
                          child: const Icon(Icons.lock_clock, size: 82, color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        const Text('المطعم مغلق حالياً', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                        const SizedBox(height: 10),
                        Text(
                          widget.state.closedMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 18),
                        const Text('يرجى المحاولة لاحقاً', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                        if (widget.onRefresh != null) ...[
                          const SizedBox(height: 18),
                          SizedBox(
                            width: 180,
                            height: 44,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                              onPressed: () async {
                                final ok = await widget.onRefresh!.call();
                                if (!mounted) return;
                                if (!ok) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يزال المطعم مغلقاً')));
                                }
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('تحديث', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
