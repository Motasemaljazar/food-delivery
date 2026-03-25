import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';
import '../theme/driver_theme.dart';

/// صفحة تفاصيل طلب واحد — معلومات الطلب + خريطة لهذا الطلب فقط.
class DriverOrderDetailScreen extends StatefulWidget {
  const DriverOrderDetailScreen({
    super.key,
    required this.order,
    required this.api,
    required this.token,
    this.restaurantLat,
    this.restaurantLng,
  });

  final Map<String, dynamic> order;
  final DriverApi api;
  final String token;
  final double? restaurantLat;
  final double? restaurantLng;

  static const int _stReadyForPickup = 3;
  static const int _stWithDriver = 4;
  static const int _stDelivered = 5;
  static const int _stCancelled = 6;
  static const int _stAccepted = 7;

  @override
  State<DriverOrderDetailScreen> createState() => _DriverOrderDetailScreenState();
}

class _DriverOrderDetailScreenState extends State<DriverOrderDetailScreen> {
  LatLng? _driverPos;
  bool _busyDeliver = false;
  bool _busyCancel = false;
  Timer? _posTimer;
  /// مسار الطريق الفعلي (على الشوارع) من OSRM — يُرسم بدل الخط المستقيم
  List<LatLng>? _roadRoutePoints;
  String? _roadRouteKey;
  DateTime? _lastRoadRouteFetch;
  bool _roadRouteLoading = false;
  /// نسخة محلية من الطلب تُحدَّث بعد «تم الاستلام» لظهور الحالة والأزرار فوراً دون انتظار القائمة
  Map<String, dynamic>? _orderData;
  final MapController _mapController = MapController();

  Map<String, dynamic> get _order => _orderData ?? widget.order;

  /// الحالة «مع السائق»: نعرض المسار وعلامات السائق والطلب فقط (بدون المطعم)
  bool get _isWithDriver => _statusCode == DriverOrderDetailScreen._stWithDriver;

  int get _statusCode =>
      (_order['currentStatus'] as num?)?.toInt() ??
      int.tryParse((_order['currentStatus'] ?? '').toString()) ?? -1;

  String _statusLabel(int s) {
    switch (s) {
      case 0: return 'جديد';
      case 1: return 'تم التأكيد';
      case 2: return 'قيد التحضير';
      case DriverOrderDetailScreen._stReadyForPickup: return 'جاهز للاستلام';
      case DriverOrderDetailScreen._stWithDriver: return 'مع السائق';
      case DriverOrderDetailScreen._stDelivered: return 'تم التسليم';
      case DriverOrderDetailScreen._stCancelled: return 'ملغى';
      case DriverOrderDetailScreen._stAccepted: return 'تم القبول';
      default: return '$s';
    }
  }

  Future<LatLng?> _getDriverPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) return null;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadDriverPos() async {
    final p = await _getDriverPosition();
    if (!mounted) return;
    if (p != null) setState(() => _driverPos = p);
    // عند «مع السائق» نحدّث مركز الخريطة كل 5 ثوان ليشمل السائق وموقع الطلب
    if (_isWithDriver && _driverPos != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final center = _center();
        _mapController.move(center, _mapController.camera.zoom);
      });
    }
  }

  /// جلب مسار الطريق الفعلي (على الشوارع) من OSRM
  static const String _osrmBase = 'https://router.project-osrm.org';

  Future<void> _fetchRoadRoute(LatLng start, LatLng end) async {
    // overview=simplified يعيد نقاطاً أقل فاستجابة أسرع مع بقاء المسار على الطرق
    final coords = '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
    final uri = Uri.parse('$_osrmBase/route/v1/driving/$coords?overview=simplified&geometries=geojson');
    if (mounted) setState(() => _roadRouteLoading = true);
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (res.statusCode != 200) {
        if (mounted) setState(() => _roadRouteLoading = false);
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (data == null || data['code'] != 'Ok') {
        if (mounted) setState(() => _roadRouteLoading = false);
        return;
      }
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        if (mounted) setState(() => _roadRouteLoading = false);
        return;
      }
      final geometry = routes[0] as Map<String, dynamic>?;
      final coordsList = geometry?['geometry']?['coordinates'] as List<dynamic>?;
      if (coordsList == null || coordsList.isEmpty) {
        if (mounted) setState(() => _roadRouteLoading = false);
        return;
      }
      // GeoJSON: [lon, lat]
      final points = coordsList
          .map((e) {
            final pair = e as List<dynamic>?;
            if (pair == null || pair.length < 2) return null;
            final lon = (pair[0] as num).toDouble();
            final lat = (pair[1] as num).toDouble();
            return LatLng(lat, lon);
          })
          .whereType<LatLng>()
          .toList();
      if (points.length >= 2 && mounted) setState(() { _roadRoutePoints = points; _roadRouteLoading = false; });
      else if (mounted) setState(() => _roadRouteLoading = false);
    } catch (_) {
      if (mounted) setState(() { _roadRoutePoints = null; _roadRouteLoading = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    _orderData = Map<String, dynamic>.from(widget.order);
    _loadDriverPos();
    // تحديث موقع السائق دورياً لتحديث خط المسار (تتبع) عند كون الطلب مع السائق
    _posTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadDriverPos());
  }

  @override
  void didUpdateWidget(covariant DriverOrderDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.order['id'] != oldWidget.order['id']) {
      _orderData = Map<String, dynamic>.from(widget.order);
      _roadRouteKey = null;
      _roadRoutePoints = null;
    }
  }

  @override
  void dispose() {
    _posTimer?.cancel();
    super.dispose();
  }

  LatLng _deliveryPoint() {
    final lat = (_order['deliveryLat'] as num?)?.toDouble();
    final lng = (_order['deliveryLng'] as num?)?.toDouble();
    if (lat != null && lng != null && (lat != 0 || lng != 0)) return LatLng(lat, lng);
    return const LatLng(33.5138, 36.2765);
  }

  LatLng _center() {
    final delivery = _deliveryPoint();
    if (_driverPos != null) {
      final bounds = LatLngBounds.fromPoints([_driverPos!, delivery]);
      return LatLng(
        (bounds.south + bounds.north) / 2,
        (bounds.west + bounds.east) / 2,
      );
    }
    return delivery;
  }

  Future<void> _markPickedUp() async {
    final id = (_order['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await widget.api.updateOrderStatus(widget.token, id, DriverOrderDetailScreen._stWithDriver);
      if (!mounted) return;
      _orderData ??= Map<String, dynamic>.from(widget.order);
      _orderData!['currentStatus'] = DriverOrderDetailScreen._stWithDriver;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم بدء التوصيل')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e')));
    }
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) * math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  Future<void> _markDelivered() async {
    final id = (_order['id'] as num?)?.toInt();
    if (id == null) return;
    final lat = (_order['deliveryLat'] as num?)?.toDouble() ?? 0.0;
    final lng = (_order['deliveryLng'] as num?)?.toDouble() ?? 0.0;
    if (lat != 0 && lng != 0) {
      final pos = await _getDriverPosition();
      if (pos != null) {
        final km = _haversineKm(pos.latitude, pos.longitude, lat, lng);
        if (km > 0.07) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('اقترب من موقع الزبون لتأكيد التسليم')),
            );
          }
          return;
        }
      }
    }
    setState(() => _busyDeliver = true);
    try {
      await widget.api.updateOrderStatus(widget.token, id, DriverOrderDetailScreen._stDelivered);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل التسليم')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyDeliver = false);
    }
  }

  Future<void> _cancelOrder() async {
    final id = (_order['id'] as num?)?.toInt();
    if (id == null) return;
    setState(() => _busyCancel = true);
    try {
      await widget.api.cancelOrder(widget.token, orderId: id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الطلب')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyCancel = false);
    }
  }

  Future<void> _callPhone(String phone) async {
    final cleaned = phone.replaceAll(' ', '');
    if (cleaned.isEmpty) return;
    await launchUrl(Uri.parse('tel:$cleaned'));
  }

  /// فتح موقع التوصيل في تطبيق خرائط جوجل
  Future<void> _openInGoogleMaps() async {
    final p = _deliveryPoint();
    final url = Uri.parse(
      'https://www.google.com/maps?q=${p.latitude},${p.longitude}',
    );
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح خرائط جوجل')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _order['id']?.toString() ?? '';
    final name = (_order['customerName'] ?? '').toString();
    final phone = (_order['customerPhone'] ?? '').toString();
    final address = (_order['deliveryAddress'] ?? '').toString();
    final total = (_order['total'] ?? '').toString();
    final status = _statusLabel(_statusCode);
    final delivery = _deliveryPoint();
    final rLat = widget.restaurantLat;
    final rLng = widget.restaurantLng;

    // عند «مع السائق»: المسار من موقع السائق إلى موقع الطلب فقط. وإلا من المطعم إلى موقع الطلب.
    final routePoints = <LatLng>[];
    final useDriverRoute = _isWithDriver;
    if (useDriverRoute && _driverPos != null) {
      routePoints.add(_driverPos!);
      routePoints.add(delivery);
    } else if (!_isWithDriver && rLat != null && rLng != null && (rLat != 0 || rLng != 0)) {
      routePoints.add(LatLng(rLat, rLng));
      routePoints.add(delivery);
    }

    // جلب مسار الطريق الفعلي (OSRM). عند «مع السائق» يُحدَّث كل 5 ثوان مع موقع السائق.
    if (routePoints.length >= 2) {
      final start = routePoints.first;
      final end = routePoints.last;
      final key = '${start.latitude},${start.longitude},${end.latitude},${end.longitude}';
      final throttleSeconds = useDriverRoute ? 5 : 15;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (key == _roadRouteKey) return;
        final throttle = _lastRoadRouteFetch != null &&
            DateTime.now().difference(_lastRoadRouteFetch!) < Duration(seconds: throttleSeconds);
        if (throttle) return;
        _roadRouteKey = key;
        _lastRoadRouteFetch = DateTime.now();
        setState(() => _roadRoutePoints = null);
        _fetchRoadRoute(start, end);
      });
    }

    final linePoints = (routePoints.length >= 2 && _roadRoutePoints != null && _roadRoutePoints!.length >= 2)
        ? _roadRoutePoints!
        : routePoints;

    final markers = <Marker>[
      Marker(
        width: 40,
        height: 40,
        point: delivery,
        child: const Icon(Icons.location_on, color: DriverTheme.primaryRed, size: 40),
      ),
    ];
    if (_driverPos != null) {
      markers.add(
        Marker(
          width: 36,
          height: 36,
          point: _driverPos!,
          child: const Icon(Icons.delivery_dining, color: Colors.green, size: 36),
        ),
      );
    }
    // عند «مع السائق» نعرض السائق وموقع الطلب فقط (بدون المطعم)
    if (!_isWithDriver && rLat != null && rLng != null && (rLat != 0 || rLng != 0)) {
      markers.add(
        Marker(
          width: 32,
          height: 32,
          point: LatLng(rLat, rLng),
          child: const Icon(Icons.restaurant, color: Colors.orange, size: 32),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('طلب #$id', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 220,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _center(),
                        initialZoom: 14,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.single.restaurant.driver',
                        ),
                    if (linePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: linePoints,
                            color: DriverTheme.primaryRed,
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: markers),
                      ],
                    ),
                    if (_roadRouteLoading)
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: DriverTheme.primaryRed),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'جاري تحميل المسار...',
                                    style: GoogleFonts.cairo(fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: _openInGoogleMaps,
                  icon: const Icon(Icons.map),
                  label: const Text('فتح موقع الطلب في خرائط جوجل'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DriverTheme.primaryRed,
                    side: const BorderSide(color: DriverTheme.primaryRed),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('الحالة', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                                Text(status, style: GoogleFonts.cairo(fontWeight: FontWeight.w700, color: DriverTheme.primaryRed)),
                              ],
                            ),
                            const Divider(height: 20),
                            _row(context, 'الزبون', name),
                            if (phone.isNotEmpty) _row(context, 'الهاتف', phone),
                            if (address.isNotEmpty) _row(context, 'العنوان', address),
                            _row(context, 'الإجمالي', '$total ل.س'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => _callPhone(phone),
                          icon: const Icon(Icons.call),
                          label: const Text('اتصال بالزبون'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DriverTheme.primaryRed,
                            side: const BorderSide(color: DriverTheme.primaryRed),
                          ),
                        ),
                      ),
                    if (_statusCode != DriverOrderDetailScreen._stDelivered &&
                        _statusCode != DriverOrderDetailScreen._stCancelled) ...[
                      if (_statusCode == DriverOrderDetailScreen._stAccepted ||
                          _statusCode == DriverOrderDetailScreen._stReadyForPickup)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FilledButton.icon(
                            onPressed: _markPickedUp,
                            icon: const Icon(Icons.play_circle_fill),
                            label: const Text('تم استلام الطلب'),
                            style: FilledButton.styleFrom(backgroundColor: DriverTheme.primaryRed),
                          ),
                        ),
                      if (_statusCode == DriverOrderDetailScreen._stWithDriver)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FilledButton.icon(
                            onPressed: _busyDeliver ? null : _markDelivered,
                            icon: _busyDeliver
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check_circle),
                            label: Text(_busyDeliver ? 'جاري...' : 'تم التسليم'),
                            style: FilledButton.styleFrom(backgroundColor: DriverTheme.primaryRed),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _busyCancel ? null : _cancelOrder,
                        icon: _busyCancel
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cancel_outlined),
                        label: const Text('إلغاء الطلب'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: GoogleFonts.cairo(fontSize: 14, color: cs.onSurfaceVariant))),
          Expanded(child: Text(value, style: GoogleFonts.cairo(fontSize: 14, color: cs.onSurface))),
        ],
      ),
    );
  }
}
