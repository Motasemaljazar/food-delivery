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
    debugPrint(
        '🔔 [Admin FCM Background] Message received: ${message.messageId}');
    debugPrint(
        '🔔 [Admin FCM Background] Title: ${message.notification?.title}');
    debugPrint('🔔 [Admin FCM Background] Body: ${message.notification?.body}');
    debugPrint('🔔 [Admin FCM Background] Data: ${message.data}');
  } catch (e) {
    debugPrint('❌ [Admin FCM Background] Error: $e');
  }
}

class AdminPushService {
  AdminPushService({required this.api, required this.platformTag});
  final AdminApi api;
  final String platformTag;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initForAdmin() async {
    if (kIsWeb) {
      debugPrint('⚠️ [Admin FCM] Web platform - FCM not initialized');
      return;
    }

    if (_initialized) {
      debugPrint('✅ [Admin FCM] Already initialized');
      return;
    }

    try {
      debugPrint('🚀 [Admin FCM] Starting initialization');

      // ✅ Step 1: Initialize Firebase
      await Firebase.initializeApp();
      debugPrint('✅ [Admin FCM] Firebase initialized');

      // ✅ Step 2: Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      debugPrint('✅ [Admin FCM] Background handler registered');

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
          debugPrint(
              '🔔 [Admin FCM] Notification tapped - payload: ${response.payload}');
          // يمكن إضافة معالجة خاصة هنا للادمن إذا لزم الأمر
        },
      );
      debugPrint('✅ [Admin FCM] Local notifications initialized');

      // ✅ Step 4: Request permissions
      if (Platform.isAndroid) {
        final androidPlugin = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidPlugin?.requestNotificationsPermission();
        debugPrint(
            '✅ [Admin FCM] Android notification permission: ${granted == true ? "GRANTED" : "DENIED"}');

        // Create notification channels
        const ordersChannel = AndroidNotificationChannel(
          'admins',
          'إشعارات الإدارة',
          description: 'إشعارات الطلبات الجديدة للإدارة',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );

        const generalChannel = AndroidNotificationChannel(
          'admin_general',
          'إشعارات عامة',
          description: 'إشعارات عامة للإدارة',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );

        await androidPlugin?.createNotificationChannel(ordersChannel);
        await androidPlugin?.createNotificationChannel(generalChannel);
        debugPrint('✅ [Admin FCM] Notification channels created');
      }

      // ✅ Step 5: Request FCM permissions
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint(
          '✅ [Admin FCM] Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('❌ [Admin FCM] Permission denied by user');
        return;
      }

      // ✅ Step 6: Subscribe to topic
      await messaging.subscribeToTopic('admins');
      debugPrint('✅ [Admin FCM] Subscribed to topic: admins');

      // ✅ Step 7: Get and register FCM token
      final fcmToken = await messaging.getToken();
      debugPrint(
          '📱 [Admin FCM] Token obtained: ${fcmToken?.substring(0, 20)}...');

      if (fcmToken != null && fcmToken.isNotEmpty) {
        try {
          await api.registerFcmAdmin(
            token: fcmToken,
            platform: platformTag,
          );
          debugPrint('✅ [Admin FCM] Token registered successfully on server');
        } catch (e) {
          debugPrint('❌ [Admin FCM] Failed to register token on server: $e');
        }
      } else {
        debugPrint('❌ [Admin FCM] Failed to obtain FCM token');
      }

      // ✅ Step 8: Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) {
        debugPrint(
            '🔄 [Admin FCM] Token refreshed: ${newToken.substring(0, 20)}...');
        api
            .registerFcmAdmin(
          token: newToken,
          platform: platformTag,
        )
            .catchError((e) {
          debugPrint('❌ [Admin FCM] Failed to register refreshed token: $e');
        });
      });

      // ✅ Step 9: Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('🔔 [Admin FCM Foreground] Message received');
        debugPrint(
            '🔔 [Admin FCM Foreground] Title: ${message.notification?.title}');
        debugPrint(
            '🔔 [Admin FCM Foreground] Body: ${message.notification?.body}');
        debugPrint('🔔 [Admin FCM Foreground] Data: ${message.data}');

        final notification = message.notification;
        if (notification == null) {
          debugPrint('⚠️ [Admin FCM Foreground] No notification payload');
          return;
        }

        final type = (message.data['type'] ?? '').toString();
        final channelId = type.isNotEmpty ? 'admin_general' : 'admins';
        final channelName =
            type.isNotEmpty ? 'إشعارات عامة' : 'إشعارات الإدارة';

        try {
          await _local.show(
            message.hashCode,
            notification.title ?? 'إشعار جديد',
            notification.body ?? '',
            NotificationDetails(
              android: AndroidNotificationDetails(
                channelId,
                channelName,
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
          debugPrint('✅ [Admin FCM Foreground] Notification displayed');
        } catch (e) {
          debugPrint(
              '❌ [Admin FCM Foreground] Failed to show notification: $e');
        }
      });

      // ✅ Step 10: Handle notification tap when app opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 [Admin FCM] App opened from notification');
        debugPrint('🔔 [Admin FCM] Data: ${message.data}');
        // يمكن إضافة معالجة خاصة هنا
      });

      // ✅ Step 11: Handle notification tap when app opened from terminated state
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 [Admin FCM] App launched from notification');
        debugPrint('🔔 [Admin FCM] Data: ${initialMessage.data}');
        // يمكن إضافة معالجة خاصة هنا
      }

      _initialized = true;
      debugPrint('✅✅✅ [Admin FCM] Initialization completed successfully! ✅✅✅');
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ [Admin FCM] Initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // ✅ Helper method to refresh token manually
  Future<void> refreshToken() async {
    if (kIsWeb) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.deleteToken();
      final newToken = await messaging.getToken();

      if (newToken != null) {
        await api.registerFcmAdmin(
          token: newToken,
          platform: platformTag,
        );
        debugPrint('✅ [Admin FCM] Token refreshed manually');
      }
    } catch (e) {
      debugPrint('❌ [Admin FCM] Manual token refresh failed: $e');
    }
  }
}

/// Customer-style push service (used by admin_app when running as customer flow).
class PushService {
  PushService({required this.api, required this.platformTag});
  final ApiClient api;
  final String platformTag;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initForCustomer({required int customerId}) async {
    if (kIsWeb) {
      debugPrint(
          '⚠️ [Admin as Customer FCM] Web platform - FCM not initialized');
      return;
    }

    if (_initialized) {
      debugPrint('✅ [Admin as Customer FCM] Already initialized');
      return;
    }

    try {
      debugPrint(
          '🚀 [Admin as Customer FCM] Starting initialization for customer: $customerId');

      // ✅ Step 1: Initialize Firebase
      await Firebase.initializeApp();
      debugPrint('✅ [Admin as Customer FCM] Firebase initialized');

      // ✅ Step 2: Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      debugPrint('✅ [Admin as Customer FCM] Background handler registered');

      // ✅ Step 3: Initialize local notifications
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      await _local
          .initialize(const InitializationSettings(android: android, iOS: iOS));
      debugPrint('✅ [Admin as Customer FCM] Local notifications initialized');

      // ✅ Step 4: Request permissions
      if (Platform.isAndroid) {
        final androidPlugin = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();

        const channel = AndroidNotificationChannel(
          'orders',
          'طلبات',
          description: 'إشعارات حالة الطلب',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );

        await androidPlugin?.createNotificationChannel(channel);
        debugPrint('✅ [Admin as Customer FCM] Notification channel created');
      }

      // ✅ Step 5: Request FCM permissions
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.subscribeToTopic('customers');
      debugPrint('✅ [Admin as Customer FCM] Subscribed to topic: customers');

      // ✅ Step 6: Get and register FCM token
      final fcmToken = await messaging.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await api.registerFcmCustomer(
          customerId: customerId,
          token: fcmToken,
          platform: platformTag,
        );
        debugPrint('✅ [Admin as Customer FCM] Token registered');
      }

      // ✅ Step 7: Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final notification = message.notification;
        if (notification == null) return;

        await _local.show(
          message.hashCode,
          notification.title ?? '',
          notification.body ?? '',
          NotificationDetails(
            android: const AndroidNotificationDetails(
              'orders',
              'طلبات',
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
      });

      _initialized = true;
      debugPrint('✅✅✅ [Admin as Customer FCM] Initialization completed! ✅✅✅');
    } catch (e, stackTrace) {
      debugPrint('❌ [Admin as Customer FCM] Initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
}
