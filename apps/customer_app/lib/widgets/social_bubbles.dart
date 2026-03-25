import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_state.dart';

class SocialBubbles extends StatelessWidget {
  const SocialBubbles({super.key, required this.state});
  final AppState state;

  Future<void> _launchUrl(BuildContext context, String url) async {
    if (url.isEmpty) return;
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح الرابط')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء فتح الرابط')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final instagram = (state.instagramUrl ?? '').trim();
    final facebook = (state.facebookUrl ?? '').trim();
    final telegram = (state.telegramUrl ?? '').trim();

    if (instagram.isEmpty && facebook.isEmpty && telegram.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (instagram.isNotEmpty) ...[
            _buildInstagramBubble(
              context: context,
              onTap: () => _launchUrl(context, instagram),
            ),
            const SizedBox(width: 14),
          ],
          if (facebook.isNotEmpty) ...[
            _buildFacebookBubble(
              context: context,
              onTap: () => _launchUrl(context, facebook),
            ),
            const SizedBox(width: 14),
          ],
          if (telegram.isNotEmpty) ...[
            _buildTelegramBubble(
              context: context,
              onTap: () => _launchUrl(context, telegram),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstagramBubble({
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFFCAF45),
              Color(0xFFFD1D1D),
              Color(0xFFE1306C),
              Color(0xFFC13584),
              Color(0xFF833AB4),
              Color(0xFF5851DB),
              Color(0xFF405DE6),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE1306C).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(34, 34),
            painter: _InstagramLogoPainter(),
          ),
        ),
      ),
    );
  }

  Widget _buildFacebookBubble({
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1877F2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1877F2).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(34, 34),
            painter: _FacebookLogoPainter(),
          ),
        ),
      ),
    );
  }

  Widget _buildTelegramBubble({
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2AABEE),
              Color(0xFF229ED9),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0088CC).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(34, 34),
            painter: _TelegramLogoPainter(),
          ),
        ),
      ),
    );
  }
}

class _InstagramLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;

    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.1,
        size.height * 0.1,
        size.width * 0.8,
        size.height * 0.8,
      ),
      Radius.circular(size.width * 0.2),
    );
    canvas.drawRRect(outerRect, paint);

    final innerCircle = Offset(size.width * 0.5, size.height * 0.5);
    canvas.drawCircle(innerCircle, size.width * 0.22, paint);

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.25),
      size.width * 0.06,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FacebookLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    
    path.moveTo(size.width * 0.58, size.height * 0.12);
    path.cubicTo(
      size.width * 0.48, size.height * 0.12,
      size.width * 0.42, size.height * 0.18,
      size.width * 0.42, size.height * 0.28,
    );
    path.lineTo(size.width * 0.42, size.height * 0.38);
    path.lineTo(size.width * 0.32, size.height * 0.38);
    path.lineTo(size.width * 0.32, size.height * 0.48);
    path.lineTo(size.width * 0.42, size.height * 0.48);
    path.lineTo(size.width * 0.42, size.height * 0.88);
    path.lineTo(size.width * 0.54, size.height * 0.88);
    path.lineTo(size.width * 0.54, size.height * 0.48);
    path.lineTo(size.width * 0.66, size.height * 0.48);
    path.lineTo(size.width * 0.68, size.height * 0.38);
    path.lineTo(size.width * 0.54, size.height * 0.38);
    path.lineTo(size.width * 0.54, size.height * 0.28);
    path.cubicTo(
      size.width * 0.54, size.height * 0.24,
      size.width * 0.56, size.height * 0.22,
      size.width * 0.60, size.height * 0.22,
    );
    path.lineTo(size.width * 0.68, size.height * 0.22);
    path.lineTo(size.width * 0.68, size.height * 0.12);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TelegramLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    
    path.moveTo(size.width * 0.15, size.height * 0.50);
    path.lineTo(size.width * 0.82, size.height * 0.18);
    path.cubicTo(
      size.width * 0.85, size.height * 0.16,
      size.width * 0.88, size.height * 0.18,
      size.width * 0.87, size.height * 0.21,
    );
    path.lineTo(size.width * 0.68, size.height * 0.85);
    path.cubicTo(
      size.width * 0.67, size.height * 0.88,
      size.width * 0.64, size.height * 0.88,
      size.width * 0.62, size.height * 0.86,
    );
    path.lineTo(size.width * 0.48, size.height * 0.68);
    path.lineTo(size.width * 0.35, size.height * 0.78);
    path.cubicTo(
      size.width * 0.33, size.height * 0.80,
      size.width * 0.30, size.height * 0.78,
      size.width * 0.30, size.height * 0.76,
    );
    path.lineTo(size.width * 0.30, size.height * 0.62);
    path.lineTo(size.width * 0.56, size.height * 0.38);
    path.lineTo(size.width * 0.38, size.height * 0.55);
    path.lineTo(size.width * 0.15, size.height * 0.50);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
