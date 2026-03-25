import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_state.dart';

/// Floating support actions (Call + WhatsApp) shown as "bubbles".
///
/// - Reads numbers from Admin Settings (supportPhone / supportWhatsApp)
/// - If both are empty, it renders nothing.
class SupportBubbles extends StatelessWidget {
  const SupportBubbles({super.key, required this.state});

  final AppState state;

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');

  Future<void> _call(String phone) async {
    final clean = _digitsOnly(phone);
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _whatsApp(String phone) async {
    // WhatsApp accepts digits only (no +) in wa.me links.
    final clean = _digitsOnly(phone).replaceAll('+', '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$clean');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final phone = state.supportPhone.trim();
    final wa = state.supportWhatsApp.trim();

    if (phone.isEmpty && wa.isEmpty) return const SizedBox.shrink();

    Widget bubble({required IconData icon, required String label, required VoidCallback onTap}) {
      return Material(
        elevation: 6,
        color: Theme.of(context).colorScheme.surface,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    // Position: bottom-left above bottom navigation.
    return Positioned(
      left: 12,
      bottom: 86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phone.isNotEmpty)
            bubble(
              icon: Icons.phone_in_talk,
              label: 'اتصال',
              onTap: () => _call(phone),
            ),
          if (phone.isNotEmpty && wa.isNotEmpty) const SizedBox(height: 10),
          if (wa.isNotEmpty)
            bubble(
              icon: Icons.chat,
              label: 'واتساب',
              onTap: () => _whatsApp(wa),
            ),
        ],
      ),
    );
  }
}
