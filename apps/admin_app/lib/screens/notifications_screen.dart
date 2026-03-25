import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/api.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.api, required this.state});
  final ApiClient api;
  final AppState state;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool loading = false;
  String? error;

  Future<void> _load() async {
    if (widget.state.customerId == null) return;
    setState(() { loading = true; error = null; });
    try {
      final list = await widget.api.listNotifications(widget.state.customerId!);
      widget.state.setNotifications(list);
    } catch (e) {
      setState(() => error = 'تعذر تحميل الإشعارات');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.state.notifications;
    // Wrap in Scaffold/Material to avoid "No Material widget found" errors
    // when this screen is pushed inside different navigators or nested builders.
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (loading && list.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (error != null && list.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(error!, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
              ]),
            );
          }
          if (list.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.notifications_none, size: 48),
                const SizedBox(height: 8),
                const Text('لا توجد إشعارات بعد', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('تحديث')),
              ]),
            );
          }

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final n = Map<String, dynamic>.from(list[i] as Map);
                final isRead = n['isRead'] == true;
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    tileColor: isRead ? null : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text((n['title'] ?? '').toString()),
                    subtitle: Text((n['body'] ?? '').toString()),
                    trailing: isRead ? const SizedBox() : const Icon(Icons.circle, size: 10),
                    onTap: () async {
                      if (widget.state.customerId == null) return;
                      try {
                        await widget.api.markNotificationRead(widget.state.customerId!, n['id'] as int);
                        await _load();
                      } catch (_) {}
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
