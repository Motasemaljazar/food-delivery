import 'package:signalr_netcore/signalr_client.dart';

class RealtimeClient {
  RealtimeClient({required this.baseUrl});
  final String baseUrl;

  HubConnection? _conn;

  Future<void> connectCustomer({required int customerId, required Function(dynamic) onNotification, required Function(Map<String, dynamic>) onOrderStatus, required Function(Map<String, dynamic>) onOrderEta, required Function(Map<String, dynamic>) onComplaintMessage, Function()? onNotificationRefresh}) async {
    await disconnect();
    final url = '${baseUrl.replaceFirst(RegExp(r'/*$'), '')}/hubs/notify';
    final c = HubConnectionBuilder().withUrl(url).withAutomaticReconnect().build();

    c.on('notification', (args) { if (args != null && args.isNotEmpty) onNotification(args[0]); });
    c.on('order_status', (args) { if (args != null && args.isNotEmpty) onOrderStatus(Map<String, dynamic>.from(args[0] as Map)); });
    c.on('order_eta', (args) { if (args != null && args.isNotEmpty) onOrderEta(Map<String, dynamic>.from(args[0] as Map)); });
    c.off('chat_message_received');
    c.on('chat_message_received', (args) { if (args != null && args.isNotEmpty) onComplaintMessage(Map<String, dynamic>.from(args[0] as Map)); });
    c.on('notification_refresh', (args) { onNotificationRefresh?.call(); });

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
