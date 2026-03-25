import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase options used for Flutter Web.
///
/// Android/iOS are configured via native google-services files.
class DefaultFirebaseOptions {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB8Z4pXf7-oXg3QuE1SsFSiHQllYn-vrK8',
    appId: '1:797032893766:web:fccd3618a85c8f8b7da947',
    messagingSenderId: '797032893766',
    projectId: 'delivary-app1-6fac2',
    authDomain: 'delivary-app1-6fac2.firebaseapp.com',
    storageBucket: 'delivary-app1-6fac2.firebasestorage.app',
  );
}
