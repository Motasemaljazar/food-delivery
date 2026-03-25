import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Bootstrap Firebase for Web without requiring flutterfire CLI.
///
/// This project ships only with `android/app/google-services.json`.
/// For Web development (`flutter run -d chrome`) we derive a working
/// [FirebaseOptions] from that file.
///
/// NOTE: For production Web hosting, it's still recommended to register a Web app
/// in Firebase Console and use the exact Web `appId`. For Auth/Messaging in dev,
/// the derived options are sufficient.
class FirebaseBootstrap {
  static Future<FirebaseOptions?> webOptionsFromGoogleServices() async {
    if (!kIsWeb) return null;
    try {
      final raw = await rootBundle.loadString('assets/firebase/google-services.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final projectInfo = (json['project_info'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final projectId = (projectInfo['project_id'] ?? '').toString();
      final senderId = (projectInfo['project_number'] ?? '').toString();
      final storageBucket = (projectInfo['storage_bucket'] ?? '').toString();

      final clientList = (json['client'] as List?) ?? const [];
      final firstClient = clientList.isNotEmpty ? (clientList.first as Map).cast<String, dynamic>() : <String, dynamic>{};
      final clientInfo = (firstClient['client_info'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final appId = (clientInfo['mobilesdk_app_id'] ?? '').toString();

      final apiKeyList = (firstClient['api_key'] as List?) ?? const [];
      final apiKey = apiKeyList.isNotEmpty ? ((apiKeyList.first as Map)['current_key'] ?? '').toString() : '';

      if (projectId.isEmpty || senderId.isEmpty || appId.isEmpty || apiKey.isEmpty) {
        return null;
      }

      return FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
        storageBucket: storageBucket,
        authDomain: '$projectId.firebaseapp.com',
      );
    } catch (_) {
      return null;
    }
  }
}
