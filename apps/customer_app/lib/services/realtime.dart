import 'package:signalr_netcore/signalr_client.dart';

class RealtimeClient {
  RealtimeClient({required this.baseUrl});
  final String baseUrl;

  HubConnection? _conn;

  Future<void> connectPublic({
    required Function() onSettingsUpdated,
    Function()? onMenuUpdated,
    Function()? onOffersUpdated,
    Function()? onCategoriesUpdated,
  }) async {
    await disconnect();
    final url = baseUrl.replaceFirst(RegExp(r'/*$'), '') + '/hubs/notify';
    final c = HubConnectionBuilder().withUrl(url).withAutomaticReconnect().build();
    c.on('settings_updated', (args) { onSettingsUpdated(); });
    c.on('menu_updated', (args) { onMenuUpdated?.call(); });
    c.on('offers_updated', (args) { onOffersUpdated?.call(); });
    c.on('categories_updated', (args) { onCategoriesUpdated?.call(); });
    await c.start();
    _conn = c;
  }

  Future<void> connectCustomer({required int customerId, required Function(dynamic) onNotification, required Function(Map<String, dynamic>) onOrderStatus, required Function(Map<String, dynamic>) onOrderEta, required Function(Map<String, dynamic>) onComplaintMessage, Function(Map<String, dynamic>)? onChatBlocked, Function()? onNotificationRefresh, Function(Map<String, dynamic>)? onSettingsUpdated, Function(Map<String, dynamic>)? onAppBlocked, Function(Map<String, dynamic>)? onAccountDeleted}) async {
    await disconnect();
    final url = baseUrl.replaceFirst(RegExp(r'/*$'), '') + '/hubs/notify';
    final c = HubConnectionBuilder().withUrl(url).withAutomaticReconnect().build();

    c.on('notification', (args) { if (args != null && args.isNotEmpty) onNotification(args[0]); });
    c.on('order_status', (args) { if (args != null && args.isNotEmpty) onOrderStatus(Map<String, dynamic>.from(args[0] as Map)); });
    c.on('order_eta', (args) { if (args != null && args.isNotEmpty) onOrderEta(Map<String, dynamic>.from(args[0] as Map)); });
    c.off('chat_message_received');
    c.on('chat_message_received', (args) { if (args != null && args.isNotEmpty) onComplaintMessage(Map<String, dynamic>.from(args[0] as Map)); });
    c.off('chat_blocked');
    c.on('chat_blocked', (args) { if (args != null && args.isNotEmpty && onChatBlocked != null) onChatBlocked(Map<String, dynamic>.from(args[0] as Map)); });
    c.on('notification_refresh', (args) { onNotificationRefresh?.call(); });
    c.on('settings_updated', (args) { if (args != null && args.isNotEmpty && onSettingsUpdated != null) onSettingsUpdated(Map<String, dynamic>.from(args[0] as Map)); });

    c.off('app_blocked');
    c.on('app_blocked', (args) {
      if (args != null && args.isNotEmpty && onAppBlocked != null) {
        onAppBlocked(Map<String, dynamic>.from(args[0] as Map));
      }
    });

    c.off('account_deleted');
    c.on('account_deleted', (args) {
      if (args != null && args.isNotEmpty && onAccountDeleted != null) {
        onAccountDeleted(Map<String, dynamic>.from(args[0] as Map));
      }
    });

    await c.start();
    await c.invoke('JoinCustomer', args: [customerId]);
    _conn = c;
  }

  Future<void> disconnect() async {
    try {
      await _conn?.stop();
    } catch (_) {}
    _conn = null;
  }
}
