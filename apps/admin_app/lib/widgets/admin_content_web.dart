// Web implementation: embed Admin Dashboard URL in an iframe.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Widget buildAdminContent({required String url}) {
  final viewType = 'admin-iframe-${url.hashCode}';

  // Register view factory once per viewType.
  // ignore: undefined_prefixed_name
  ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'white'
      ..allowFullscreen = true;

    return iframe;
  });

  return HtmlElementView(viewType: viewType);
}
