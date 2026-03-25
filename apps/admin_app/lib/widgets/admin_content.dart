import 'package:flutter/widgets.dart';

// Conditional import:
// - Web: uses iframe
// - Mobile: uses webview_flutter
// - Others: stub message
import 'admin_content_stub.dart'
    if (dart.library.html) 'admin_content_web.dart'
    if (dart.library.io) 'admin_content_mobile.dart';

/// Returns a Widget that renders the Admin Dashboard URL.
Widget adminContent({required String url}) {
  return buildAdminContent(url: url);
}
