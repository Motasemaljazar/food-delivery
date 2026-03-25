import 'package:signalr_netcore/signalr_client.dart';

class RealtimeClient {
  RealtimeClient({required this.baseUrl});
  final String baseUrl;

  HubConnection? _conn;

  Future<void> connectDriver({
    required String token,
    Function(Map<String, dynamic>)? onSettingsUpdated,
    Function(Map<String, dynamic>)? onOrderAssigned,
    Function(Map<String, dynamic>)? onOrderUpdated,
  }) async {
    await disconnect();
    final url = baseUrl.replaceFirst(RegExp(r'/*$'), '') + '/hubs/notify';
    final c = HubConnectionBuilder().withUrl(url).withAutomaticReconnect().build();

    c.on('settings_updated', (args) {
      if (args != null && args.isNotEmpty && onSettingsUpdated != null) {
        onSettingsUpdated(Map<String, dynamic>.from(args[0] as Map));
      }
    });

    c.on('driver_order', (args) {
      if (args != null && args.isNotEmpty && onOrderAssigned != null) {
        onOrderAssigned(Map<String, dynamic>.from(args[0] as Map));
      }
    });

    c.on('order_assigned', (args) {
      if (args != null && args.isNotEmpty && onOrderAssigned != null) {
        onOrderAssigned(Map<String, dynamic>.from(args[0] as Map));
      }
    });

    c.on('order_edited', (args) {
      if (args != null && args.isNotEmpty && onOrderUpdated != null) {
        onOrderUpdated(Map<String, dynamic>.from(args[0] as Map));
      }
    });

    await c.start();
    await c.invoke('JoinDriver', args: [token]);
    _conn = c;
  }

  Future<void> disconnect() async {
    try { await _conn?.stop(); } catch (_) {}
    _conn = null;
  }
}
