import 'package:flutter/widgets.dart';

/// Fallback for unsupported platforms.
Widget buildAdminContent({required String url}) {
  return const Center(
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Text('هذه المنصة غير مدعومة حاليًا.'),
    ),
  );
}
