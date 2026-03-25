import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/admin_api.dart';

/// الخريطة الحية — موقع المطعم، الطلبات النشطة، مواقع السائقين.
class AdminLiveMapScreen extends StatefulWidget {
  const AdminLiveMapScreen(
      {super.key, required this.api, this.selectedTabIndex});
  final AdminApiService api;

  /// index تبويب الخريطة في الشريط السفلي (عند الظهور نحدّث الخريطة فوراً)
  final int? selectedTabIndex;

  static const int kMapTabIndex = 4;

  @override
  State<AdminLiveMapScreen> createState() => _AdminLiveMapScreenState();
}

class _AdminLiveMapScreenState extends State<AdminLiveMapScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  int? _prevTabIndex;

  bool get _isMapVisible =>
      widget.selectedTabIndex == AdminLiveMapScreen.kMapTabIndex;

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    // تحديث الخريطة فقط عندما يكون تبويب الخريطة مفتوحاً
    if (_isMapVisible) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    }
  }

  @override
  void initState() {
    super.initState();
    _prevTabIndex = widget.selectedTabIndex;
    if (_isMapVisible) _load();
    _startTimer();
  }

  @override
  void didUpdateWidget(AdminLiveMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = widget.selectedTabIndex;
    if (now != null &&
        now == AdminLiveMapScreen.kMapTabIndex &&
        _prevTabIndex != now) {
      _load();
    }
    if (now != _prevTabIndex) {
      _startTimer();
    }
    _prevTabIndex = now;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final data = await widget.api.getLiveMapData();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('AdminApiException:', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final restaurant = _data!['restaurant'] as Map<String, dynamic>?;
    final orders = _data!['orders'] as List<dynamic>? ?? [];
    final driverLocs = _data!['driverLocations'] as List<dynamic>? ?? [];

    double lat = 33.5138;
    double lng = 36.2765;
    if (restaurant != null) {
      final rLat = restaurant['lat'];
      final rLng = restaurant['lng'];
      if (rLat != null && rLng != null) {
        final rLatD =
            (rLat is num) ? rLat.toDouble() : double.tryParse(rLat.toString());
        final rLngD =
            (rLng is num) ? rLng.toDouble() : double.tryParse(rLng.toString());
        if (rLatD != null && rLngD != null && (rLatD != 0 || rLngD != 0)) {
          lat = rLatD;
          lng = rLngD;
        }
      }
    }

    final center = LatLng(lat, lng);
    final markers = <Marker>[];

    // مطعم
    markers.add(
      Marker(
        point: center,
        width: 40,
        height: 40,
        child: const Icon(Icons.restaurant, color: Colors.orange, size: 40),
      ),
    );

    // طلبات (عنوان التوصيل) — تحت كل طلب رقم الطلب
    for (final o in orders) {
      final dLatRaw = o['deliveryLat'];
      final dLngRaw = o['deliveryLng'];
      final dLat = dLatRaw is num
          ? dLatRaw.toDouble()
          : (dLatRaw != null ? double.tryParse(dLatRaw.toString()) : null);
      final dLng = dLngRaw is num
          ? dLngRaw.toDouble()
          : (dLngRaw != null ? double.tryParse(dLngRaw.toString()) : null);
      if (dLat != null && dLng != null && (dLat != 0 || dLng != 0)) {
        final orderId = o['id']?.toString() ?? '?';
        markers.add(
          Marker(
            point: LatLng(dLat, dLng),
            width: 84,
            height: 56,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_on,
                  color: _statusColor(o['currentStatus']?.toString()),
                  size: 28,
                ),
                const SizedBox(height: 1),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3,
                          offset: const Offset(0, 1))
                    ],
                  ),
                  child: Text('طلب #$orderId',
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      }
    }

    // مواقع السائقين — تحت كل سائق اسمه
    for (final loc in driverLocs) {
      final latRaw = loc['lat'];
      final lngRaw = loc['lng'];
      final locLat = latRaw is num
          ? latRaw.toDouble()
          : (latRaw != null ? double.tryParse(latRaw.toString()) : null);
      final locLng = lngRaw is num
          ? lngRaw.toDouble()
          : (lngRaw != null ? double.tryParse(lngRaw.toString()) : null);
      if (locLat != null && locLng != null) {
        final driverName = (loc['driverName'] ?? 'سائق').toString().trim();
        final name =
            driverName.isEmpty ? 'سائق #${loc['driverId'] ?? '?'}' : driverName;
        markers.add(
          Marker(
            point: LatLng(locLat, locLng),
            width: 100,
            height: 58,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.delivery_dining,
                    color: Colors.green, size: 30),
                const SizedBox(height: 1),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3,
                          offset: const Offset(0, 1))
                    ],
                  ),
                  child: Text(name.isEmpty ? 'سائق' : name,
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.topchef.admin',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          left: 16,
          top: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.restaurant, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(restaurant?['name']?.toString() ?? 'المطعم',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'طلبات نشطة: ${orders.length}  |  سائقون على الخريطة: ${driverLocs.length}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: IconButton.filled(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'تحديث',
          ),
        ),
      ],
    );
  }

  Color _statusColor(String? status) {
    if (status == null) return Colors.grey;
    if (status.contains('WithDriver')) return Colors.blue;
    if (status.contains('Ready') || status.contains('Preparing'))
      return Colors.amber;
    return Colors.red;
  }
}
