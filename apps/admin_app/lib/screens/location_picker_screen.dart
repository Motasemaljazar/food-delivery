import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LatLngResult {
  final double lat;
  final double lng;
  LatLngResult(this.lat, this.lng);
}

/// Map picker (SRS):
/// - OpenStreetMap tiles
/// - User pans/zooms the map
/// - Marker is fixed at the center (Google Maps-like)
/// - GPS auto-locate button
/// - Center marker is a pulsing circle (not an arrow)
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen(
      {super.key, required this.initialLat, required this.initialLng});
  final double initialLat;
  final double initialLng;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with SingleTickerProviderStateMixin {
  late final MapController _controller;
  late LatLng _center;

  late final AnimationController _pulse;
  Timer? _debounce;

  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _controller = MapController();
    _center = LatLng(widget.initialLat, widget.initialLng);
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onMove(MapPosition position, bool _) {
    final c = position.center;
    if (c != null) _center = c;
  }

  Future<void> _gotoMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('يرجى تفعيل خدمة الموقع (GPS)');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        throw Exception('تم رفض إذن الموقع');
      }
      if (perm == LocationPermission.deniedForever) {
        throw Exception(
            'إذن الموقع مرفوض نهائياً. افتح الإعدادات وفعّل الإذن.');
      }

      final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final target = LatLng(p.latitude, p.longitude);
      _controller.move(target, 17);
      _center = target;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تحديد موقعك تلقائياً')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحديد موقع التوصيل'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                  context, LatLngResult(_center.latitude, _center.longitude)),
              child: const Text('تأكيد',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 16,
                onPositionChanged: (position, _) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 50),
                      () => _onMove(position, _));
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.single.restaurant.admin',
                ),
              ],
            ),

            // Fixed center marker (pulse circle)
            IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (ctx, _) {
                    final t = _pulse.value; // 0..1
                    final scale = 0.6 + (t * 0.8);
                    final opacity = (1.0 - t).clamp(0.0, 1.0);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: 0.35 * opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    width: 3,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primary,
                            boxShadow: const [
                              BoxShadow(
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                  color: Colors.black26)
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            Positioned(
              right: 12,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: 'gps',
                onPressed: _locating ? null : _gotoMyLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_outlined),
                label: const Text('تحديد تلقائي'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
