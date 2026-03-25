import 'package:flutter/material.dart';

import '../services/admin_api.dart';

class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  List<dynamic> _drivers = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.getDrivers();
      if (mounted) setState(() {
        _drivers = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('AdminApiException:', '');
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const List<String> _statusNames = ['متاح', 'مشغول', 'غير متصل'];

  @override
  Widget build(BuildContext context) {
    if (_loading && _drivers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _drivers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        itemCount: _drivers.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return const SizedBox(height: 8);
          final d = _drivers[i - 1] as Map<String, dynamic>;
          final id = d['id'] as int? ?? 0;
          final name = d['name'] as String? ?? 'سائق #$id';
          final phone = d['phone'] as String?;
          final status = d['status'] as int? ?? 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
              ),
              title: Text(name),
              subtitle: phone != null && phone.isNotEmpty
                  ? Text(phone, style: TextStyle(fontSize: 13, color: Colors.grey[600]))
                  : null,
              trailing: Chip(
                label: Text(_statusNames[status > 2 ? 0 : status], style: const TextStyle(fontSize: 12)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          );
        },
      ),
    );
  }
}
