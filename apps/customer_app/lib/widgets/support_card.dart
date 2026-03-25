import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_state.dart';

class SupportCard extends StatelessWidget {
  const SupportCard({super.key, required this.state});
  final AppState state;

  String _cleanPhone(String input) {
    var v = input.trim();
    v = v.replaceAll(' ', '');
    v = v.replaceAll('-', '');
    v = v.replaceAll('(', '');
    v = v.replaceAll(')', '');
    v = v.replaceAll('+', '');
    return v;
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تنفيذ العملية')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = state.supportPhone.trim();
    final wa = state.supportWhatsApp.trim();
    if (phone.isEmpty && wa.isEmpty) return const SizedBox();

    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.support_agent, color: cs.primary),
                const SizedBox(width: 10),
                const Text('الدعم', style: TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 10),
            if (phone.isNotEmpty) Text('هاتف: $phone', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (wa.isNotEmpty) Text('واتساب: $wa', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (phone.isNotEmpty)
                  FilledButton.icon(
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('اتصال'),
                    onPressed: () => _launch(context, Uri.parse('tel:$phone')),
                  ),
                if (wa.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('واتساب'),
                    onPressed: () {
                      final num = _cleanPhone(wa);
                      _launch(context, Uri.parse('https://wa.me/$num'));
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
