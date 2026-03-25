import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// شاشة اختيار موقع المطعم على الخريطة — المستخدم يحرك الخريطة ثم يضغط "تم".
class AdminMapPickerScreen extends StatefulWidget {
  const AdminMapPickerScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  final double initialLat;
  final double initialLng;

  @override
  State<AdminMapPickerScreen> createState() => _AdminMapPickerScreenState();
}

class _AdminMapPickerScreenState extends State<AdminMapPickerScreen> {
  late final MapController _mapController;
  late double _lat;
  late double _lng;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
    if (_lat == 0 && _lng == 0) {
      _lat = 33.5138;
      _lng = 36.2765;
    }
  }

  void _onMapMove(MapPosition position) {
    final center = position.center;
    if (center == null) return;
    setState(() {
      _lat = center.latitude;
      _lng = center.longitude;
    });
  }

  void _confirm() {
    Navigator.of(context).pop<LatLng>(LatLng(_lat, _lng));
  }

  Future<void> _goToMyLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تفعيل خدمة الموقع في الجهاز أولاً')),
        );
      }
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب السماح بالوصول إلى الموقع')),
        );
      }
      return;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });
      _mapController.move(LatLng(_lat, _lng), 16);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحصول على الموقع: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(_lat, _lng);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحديد موقع المطعم'),
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                onPositionChanged: (position, _) => _onMapMove(position),
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.topchef.admin',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 48,
                      height: 48,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 48),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: SafeArea(
                child: OutlinedButton.icon(
                  onPressed: _goToMyLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text('تحديد موقعي الآن'),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'حرّك الخريطة لوضع الدبوس على موقع المطعم أو استخدم "تحديد موقعي الآن" ثم اضغط تم',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check),
                      label: const Text('تم'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
