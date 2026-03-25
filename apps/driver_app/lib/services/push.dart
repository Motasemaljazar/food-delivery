import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api.dart';

// ✅ Background handler must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  
  try {
    await Firebase.initializeApp();
    debugPrint('🔔 [Driver FCM Background] Message received: ${message.messageId}');
    debugPrint('🔔 [Driver FCM Background] Title: ${message.notification?.title}');
    debugPrint('🔔 [Driver FCM Background] Body: ${message.notification?.body}');
    debugPrint('🔔 [Driver FCM Background] Data: ${message.data}');
  } catch (e) {
    debugPrint('❌ [Driver FCM Background] Error: $e');
  }
}

class DriverPushService {
  DriverPushService({required this.api, required this.platformTag});
  final DriverApi api;
  final String platformTag;

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initForDriver({required String driverToken}) async {
    if (kIsWeb) {
      debugPrint('⚠️ [Driver FCM] Web platform - FCM not initialized');
      return;
    }

    if (_initialized) {
      debugPrint('✅ [Driver FCM] Already initialized');
      return;
    }

    try {
      debugPrint('🚀 [Driver FCM] Starting initialization');

      // ✅ Step 1: Initialize Firebase
      await Firebase.initializeApp();
      debugPrint('✅ [Driver FCM] Firebase initialized');

      // ✅ Step 2: Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      debugPrint('✅ [Driver FCM] Background handler registered');

      // ✅ Step 3: Initialize local notifications
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      await _local.initialize(
        const InitializationSettings(android: android, iOS: iOS),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('🔔 [Driver FCM] Notification tapped - payload: ${response.payload}');
          // يمكن إضافة معالجة خاصة هنا للسائق إذا لزم الأمر
        },
      );
      debugPrint('✅ [Driver FCM] Local notifications initialized');

      // ✅ Step 4: Request permissions
      if (Platform.isAndroid) {
        final androidPlugin = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidPlugin?.requestNotificationsPermission();
        debugPrint('✅ [Driver FCM] Android notification permission: ${granted == true ? "GRANTED" : "DENIED"}');
        
        // Create notification channel
        const channel = AndroidNotificationChannel(
          'orders',
          'طلبات التوصيل',
          description: 'إشعارات مهام التوصيل',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );
        
        await androidPlugin?.createNotificationChannel(channel);
        debugPrint('✅ [Driver FCM] Notification channel created');
      }

      // ✅ Step 5: Request FCM permissions
      final messaging = FirebaseMessaging.instance;
      
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      debugPrint('✅ [Driver FCM] Permission status: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('❌ [Driver FCM] Permission denied by user');
        return;
      }

      // ✅ Step 6: Subscribe to topic
      await messaging.subscribeToTopic('drivers');
      debugPrint('✅ [Driver FCM] Subscribed to topic: drivers');

      // ✅ Step 7: Get and register FCM token
      final fcmToken = await messaging.getToken();
      debugPrint('📱 [Driver FCM] Token obtained: ${fcmToken?.substring(0, 20)}...');
      
      if (fcmToken != null && fcmToken.isNotEmpty) {
        try {
          await api.registerFcmDriver(
            driverToken,
            token: fcmToken,
            platform: platformTag,
          );
          debugPrint('✅ [Driver FCM] Token registered successfully on server');
        } catch (e) {
          debugPrint('❌ [Driver FCM] Failed to register token on server: $e');
        }
      } else {
        debugPrint('❌ [Driver FCM] Failed to obtain FCM token');
      }

      // ✅ Step 8: Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 [Driver FCM] Token refreshed: ${newToken.substring(0, 20)}...');
        api.registerFcmDriver(
          driverToken,
          token: newToken,
          platform: platformTag,
        ).catchError((e) {
          debugPrint('❌ [Driver FCM] Failed to register refreshed token: $e');
        });
      });

      // ✅ Step 9: Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('🔔 [Driver FCM Foreground] Message received');
        debugPrint('🔔 [Driver FCM Foreground] Title: ${message.notification?.title}');
        debugPrint('🔔 [Driver FCM Foreground] Body: ${message.notification?.body}');
        debugPrint('🔔 [Driver FCM Foreground] Data: ${message.data}');

        final notification = message.notification;
        if (notification == null) {
          debugPrint('⚠️ [Driver FCM Foreground] No notification payload');
          return;
        }

        try {
          await _local.show(
            message.hashCode,
            notification.title ?? 'طلب توصيل جديد',
            notification.body ?? '',
            NotificationDetails(
              android: const AndroidNotificationDetails(
                'orders',
                'طلبات التوصيل',
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
                icon: '@mipmap/ic_launcher',
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
            payload: jsonEncode(message.data),
          );
          debugPrint('✅ [Driver FCM Foreground] Notification displayed');
        } catch (e) {
          debugPrint('❌ [Driver FCM Foreground] Failed to show notification: $e');
        }
      });

      // ✅ Step 10: Handle notification tap when app opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 [Driver FCM] App opened from notification');
        debugPrint('🔔 [Driver FCM] Data: ${message.data}');
        // يمكن إضافة معالجة خاصة هنا
      });

      // ✅ Step 11: Handle notification tap when app opened from terminated state
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 [Driver FCM] App launched from notification');
        debugPrint('🔔 [Driver FCM] Data: ${initialMessage.data}');
        // يمكن إضافة معالجة خاصة هنا
      }

      _initialized = true;
      debugPrint('✅✅✅ [Driver FCM] Initialization completed successfully! ✅✅✅');
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ [Driver FCM] Initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // ✅ Helper method to refresh token manually
  Future<void> refreshToken(String driverToken) async {
    if (kIsWeb) return;
    
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.deleteToken();
      final newToken = await messaging.getToken();
      
      if (newToken != null) {
        await api.registerFcmDriver(
          driverToken,
          token: newToken,
          platform: platformTag,
        );
        debugPrint('✅ [Driver FCM] Token refreshed manually');
      }
    } catch (e) {
      debugPrint('❌ [Driver FCM] Manual token refresh failed: $e');
    }
  }
}
