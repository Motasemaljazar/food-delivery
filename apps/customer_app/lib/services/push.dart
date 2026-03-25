import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/api.dart';
import '../services/app_refs.dart';
import '../main.dart' show appNavigatorKey;
import '../screens/order_details_screen.dart';
import '../screens/complaints_screen.dart';
import '../screens/home_screen.dart';

// ✅ Background handler must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;

  try {
    await Firebase.initializeApp();
    debugPrint('🔔 [FCM Background] Message received: ${message.messageId}');
    debugPrint('🔔 [FCM Background] Title: ${message.notification?.title}');
    debugPrint('🔔 [FCM Background] Body: ${message.notification?.body}');
    debugPrint('🔔 [FCM Background] Data: ${message.data}');
  } catch (e) {
    debugPrint('❌ [FCM Background] Error: $e');
  }
}

class PushService {
  PushService({required this.api, required this.platformTag});
  final ApiClient api;
  final String platformTag;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  void _handleOpen(Map<String, dynamic> data) {
    final nav = appNavigatorKey.currentState;
    final api = AppRefs.api;
    final state = AppRefs.state;
    if (nav == null || api == null || state == null) {
      debugPrint(
          '⚠️ [FCM] Cannot handle notification tap - missing dependencies');
      return;
    }

    final type = (data['type'] ?? data['kind'] ?? '').toString();
    final orderId = int.tryParse((data['orderId'] ?? '').toString());

    debugPrint(
        '🔔 [FCM] Handling notification tap - Type: $type, OrderId: $orderId');

    if (type == 'chat') {
      nav.push(MaterialPageRoute(
        builder: (_) => ComplaintsScreen(api: api, state: state),
      ));
      return;
    }

    if (type == 'new_offer') {
      nav.pushNamedAndRemoveUntil(HomeScreen.route, (_) => false);
      return;
    }

    if (orderId != null && orderId > 0) {
      nav.push(MaterialPageRoute(
        builder: (_) =>
            OrderDetailsScreen(api: api, state: state, orderId: orderId),
      ));
    }
  }

  Future<void> initForCustomer({required int customerId}) async {
    if (kIsWeb) {
      debugPrint('⚠️ [FCM] Web platform - FCM not initialized');
      return;
    }

    if (_initialized) {
      debugPrint('✅ [FCM] Already initialized');
      return;
    }

    try {
      debugPrint('🚀 [FCM] Starting initialization for customer: $customerId');

      // ✅ Step 1: Initialize Firebase
      await Firebase.initializeApp();
      debugPrint('✅ [FCM] Firebase initialized');

      // ✅ Step 2: Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      debugPrint('✅ [FCM] Background handler registered');

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
              '🔔 [FCM] Notification tapped - payload: ${response.payload}');
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;

          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            _handleOpen(data);
          } catch (e) {
            debugPrint('❌ [FCM] Error parsing notification payload: $e');
          }
        },
      );
      debugPrint('✅ [FCM] Local notifications initialized');

      // ✅ Step 4: Request permissions
      if (Platform.isAndroid) {
        final androidPlugin = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidPlugin?.requestNotificationsPermission();
        debugPrint(
            '✅ [FCM] Android notification permission: ${granted == true ? "GRANTED" : "DENIED"}');

        // Create notification channels
        const ordersChannel = AndroidNotificationChannel(
          'orders',
          'طلبات',
          description: 'إشعارات حالة الطلب',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );

        const chatChannel = AndroidNotificationChannel(
          'chat',
          'دردشة مع المطعم',
          description: 'رسائل الدردشة مع المطعم',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );

        await androidPlugin?.createNotificationChannel(ordersChannel);
        await androidPlugin?.createNotificationChannel(chatChannel);
        debugPrint('✅ [FCM] Notification channels created');
      }

      // ✅ Step 5: Request FCM permissions
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('✅ [FCM] Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('❌ [FCM] Permission denied by user');
        return;
      }

      // ✅ Step 6: Subscribe to topic
      await messaging.subscribeToTopic('customers');
      debugPrint('✅ [FCM] Subscribed to topic: customers');

      // ✅ Step 7: Get and register FCM token
      final token = await messaging.getToken();
      debugPrint('📱 [FCM] Token obtained: ${token?.substring(0, 20)}...');
      // للاختبار في Firebase Console: انسخ الرمز الكامل من السطر التالي
      if (token != null && token.isNotEmpty) {
        debugPrint('📋 [FCM] Full token (copy for Firebase test): $token');
      }
      if (token != null && token.isNotEmpty) {
        try {
          await api.registerFcmCustomer(
            customerId: customerId,
            token: token,
            platform: platformTag,
          );
          debugPrint('✅ [FCM] Token registered successfully on server');
        } catch (e) {
          debugPrint('❌ [FCM] Failed to register token on server: $e');
        }
      } else {
        debugPrint('❌ [FCM] Failed to obtain FCM token');
      }

      // ✅ Step 8: Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 [FCM] Token refreshed: ${newToken.substring(0, 20)}...');
        api
            .registerFcmCustomer(
          customerId: customerId,
          token: newToken,
          platform: platformTag,
        )
            .catchError((e) {
          debugPrint('❌ [FCM] Failed to register refreshed token: $e');
        });
      });

      // ✅ Step 9: Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('🔔 [FCM Foreground] Message received');
        debugPrint('🔔 [FCM Foreground] Title: ${message.notification?.title}');
        debugPrint('🔔 [FCM Foreground] Body: ${message.notification?.body}');
        debugPrint('🔔 [FCM Foreground] Data: ${message.data}');

        final notification = message.notification;
        if (notification == null) {
          debugPrint('⚠️ [FCM Foreground] No notification payload');
          return;
        }

        final type = (message.data['type'] ?? '').toString();
        final channelId = type == 'chat' ? 'chat' : 'orders';
        final channelName = type == 'chat' ? 'دردشة مع المطعم' : 'طلبات';

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
          debugPrint('✅ [FCM Foreground] Notification displayed');
        } catch (e) {
          debugPrint('❌ [FCM Foreground] Failed to show notification: $e');
        }
      });

      // ✅ Step 10: Handle notification tap when app opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 [FCM] App opened from notification');
        debugPrint('🔔 [FCM] Data: ${message.data}');
        if (message.data.isNotEmpty) {
          _handleOpen(Map<String, dynamic>.from(message.data));
        }
      });

      // ✅ Step 11: Handle notification tap when app opened from terminated state
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 [FCM] App launched from notification');
        debugPrint('🔔 [FCM] Data: ${initialMessage.data}');
        if (initialMessage.data.isNotEmpty) {
          // Delay to ensure app is fully initialized
          Future.delayed(const Duration(seconds: 1), () {
            _handleOpen(Map<String, dynamic>.from(initialMessage.data));
          });
        }
      }

      _initialized = true;
      debugPrint('✅✅✅ [FCM] Initialization completed successfully! ✅✅✅');
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ [FCM] Initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // ✅ Helper method to refresh token manually
  Future<void> refreshToken(int customerId) async {
    if (kIsWeb) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.deleteToken();
      final newToken = await messaging.getToken();

      if (newToken != null) {
        await api.registerFcmCustomer(
          customerId: customerId,
          token: newToken,
          platform: platformTag,
        );
        debugPrint('✅ [FCM] Token refreshed manually');
      }
    } catch (e) {
      debugPrint('❌ [FCM] Manual token refresh failed: $e');
    }
  }
}
