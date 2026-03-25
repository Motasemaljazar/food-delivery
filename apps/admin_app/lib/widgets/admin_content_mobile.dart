import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

Widget buildAdminContent({required String url}) {
  return _AdminWebView(url: url);
}

class _AdminWebView extends StatefulWidget {
  const _AdminWebView({required this.url});
  final String url;

  @override
  State<_AdminWebView> createState() => _AdminWebViewState();
}

class _AdminWebViewState extends State<_AdminWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController(widget.url);
    WidgetsBinding.instance.addPostFrameCallback((_) => _configureAndroidIfNeeded());
  }

  WebViewController _createController(String url) {
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();

    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(params);
    }

    final ctrl = WebViewController.fromPlatformCreationParams(params);
    ctrl.setJavaScriptMode(JavaScriptMode.unrestricted);
    ctrl.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (String pageUrl) {
          _injectViewportForMobile(ctrl);
        },
        onWebResourceError: (error) {
          debugPrint('WebView error: ${error.description}');
        },
      ),
    );
    ctrl.loadRequest(Uri.parse(url));
    return ctrl;
  }

  Future<void> _configureAndroidIfNeeded() async {
    if (!Platform.isAndroid) return;
    final android = _controller.platform;
    if (android is AndroidWebViewController) {
      await android.enableZoom(true);
    }
  }

  /// يحقن viewport مناسب للشاشات الصغيرة لتحسين العرض على أندرويد
  static Future<void> _injectViewportForMobile(WebViewController controller) async {
    const String js = '''
      (function() {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
      })();
    ''';
    try {
      await controller.runJavaScript(js);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
