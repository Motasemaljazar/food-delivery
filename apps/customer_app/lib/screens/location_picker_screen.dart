import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class LatLngResult {
  final double lat;
  final double lng;
  LatLngResult(this.lat, this.lng);
}

class SearchResult {
  final String displayName;
  final double lat;
  final double lon;

  SearchResult({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      displayName: json['display_name'] ?? '',
      lat: double.tryParse(json['lat']?.toString() ?? '0') ?? 0,
      lon: double.tryParse(json['lon']?.toString() ?? '0') ?? 0,
    );
  }
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.confirmLabel = 'تأكيد الموقع',
  });
  final double initialLat;
  final double initialLng;
  final String confirmLabel;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with SingleTickerProviderStateMixin {
  late final MapController _controller;
  late LatLng _center;

  late final AnimationController _pulse;
  Timer? _debounce;
  Timer? _searchDebounce;

  bool _locating = false;
  bool _searching = false;
  bool _showSearchResults = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<SearchResult> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _controller = MapController();
    _center = LatLng(widget.initialLat, widget.initialLng);
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();

    _searchController.addListener(_onSearchChanged);
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus && _searchController.text.isEmpty) {
        setState(() => _showSearchResults = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _pulse.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    if (_searchController.text.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(_searchController.text);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() => _searching = true);

    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=10&accept-language=ar');

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'RestaurantApp/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _searchResults =
              data.map((json) => SearchResult.fromJson(json)).toList();
          _showSearchResults = _searchResults.isNotEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في البحث: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSearchResult(SearchResult result) {
    final target = LatLng(result.lat, result.lon);
    _controller.move(target, 16);
    _center = target;
    setState(() {
      _showSearchResults = false;
      _searchController.clear();
    });
    _searchFocus.unfocus();
  }

  void _onMove(MapCamera camera, bool _) {
    _center = camera.center;
  }

  Future<void> _gotoMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('يرجى تفعيل خدمة الموقع (GPS)');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied)
        throw Exception('تم رفض إذن الموقع');
      if (perm == LocationPermission.deniedForever)
        throw Exception(
            'إذن الموقع مرفوض نهائياً. افتح الإعدادات وفعّل الإذن.');

      final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final target = LatLng(p.latitude, p.longitude);
      _controller.move(target, 17);
      _center = target;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تحديد موقعك تلقائياً')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحديد موقع التوصيل'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                  context, LatLngResult(_center.latitude, _center.longitude)),
              child: Text(widget.confirmLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w900,
                  )),
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
                onPositionChanged: (camera, _) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 50),
                      () => _onMove(camera, _));
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.single.restaurant.customer',
                ),
              ],
            ),
            IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (ctx, _) {
                    final t = _pulse.value;
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
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocus,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: cs.onSurface),
                                decoration: InputDecoration(
                                  hintText: 'ابحث عن مدينة، شارع، منطقة...',
                                  border: InputBorder.none,
                                  hintStyle: theme.textTheme.bodyMedium
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                                textDirection: TextDirection.rtl,
                                onTap: () {
                                  if (_searchResults.isNotEmpty) {
                                    setState(() => _showSearchResults = true);
                                  }
                                },
                              ),
                            ),
                            if (_searching)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            else if (_searchController.text.isNotEmpty)
                              IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  size: 20,
                                  color: cs.onSurfaceVariant,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchResults = [];
                                    _showSearchResults = false;
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                      if (_showSearchResults && _searchResults.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 300),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(12),
                            ),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final result = _searchResults[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.location_on,
                                  color: cs.primary,
                                  size: 20,
                                ),
                                title: Text(
                                  result.displayName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 14,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: TextDirection.rtl,
                                ),
                                onTap: () => _selectSearchResult(result),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 74,
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
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: IgnorePointer(
                ignoring: _locating,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context,
                          LatLngResult(_center.latitude, _center.longitude)),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(widget.confirmLabel),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
