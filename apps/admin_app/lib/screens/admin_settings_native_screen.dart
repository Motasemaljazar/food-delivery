import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../services/admin_api.dart';
import '../services/admin_auth_storage.dart';
import 'admin_login_screen.dart';
import 'admin_map_picker_screen.dart';

class AdminSettingsNativeScreen extends StatefulWidget {
  const AdminSettingsNativeScreen({super.key, required this.api});
  final AdminApiService api;

  @override
  State<AdminSettingsNativeScreen> createState() =>
      _AdminSettingsNativeScreenState();
}

class _AdminSettingsNativeScreenState extends State<AdminSettingsNativeScreen> {
  Map<String, dynamic>? _settings;
  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _uploadingLogo = false;

  final Map<String, TextEditingController> _controllers = {};
  final ImagePicker _imagePicker = ImagePicker();

  TextEditingController _ctrl(String key) {
    if (!_controllers.containsKey(key)) {
      _controllers[key] = TextEditingController();
    }
    return _controllers[key]!;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.api.getSettings();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _loading = false;
        _fillControllers(s);
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().replaceFirst('AdminApiException:', '');
          _loading = false;
        });
    }
  }

  void _fillControllers(Map<String, dynamic> s) {
    void set(String key, dynamic value) {
      final c = _ctrl(key);
      if (value == null) {
        c.text = '';
      } else {
        c.text = value is num ? value.toString() : (value.toString());
      }
    }

    set('restaurantName', s['restaurantName']);
    set('workHours', s['workHours']);
    set('closedMessage', s['closedMessage'] ?? 'المطعم مغلق حالياً');
    set('deliveryFeePerKm', s['deliveryFeePerKm']);
    set('supportPhone', s['supportPhone']);
    set('supportWhatsApp', s['supportWhatsApp']);
    set('logoUrl', s['logoUrl']);
    set('restaurantLat', s['restaurantLat']);
    set('restaurantLng', s['restaurantLng']);
  }

  Future<void> _pickAndUploadLogo() async {
    final XFile? picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    if (!file.existsSync()) return;
    setState(() => _uploadingLogo = true);
    try {
      final url = await widget.api.uploadAsset(file, kind: 'logo');
      if (!mounted) return;
      setState(() {
        _uploadingLogo = false;
        _ctrl('logoUrl').text = url;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع الشعار. اضغط حفظ الإعدادات لتطبيقه.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingLogo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('AdminApiException:', ''))),
        );
      }
    }
  }

  String? _logoPreviewUrl() {
    final url = _ctrl('logoUrl').text.trim();
    if (url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    final base = widget.api.baseUrl.endsWith('/')
        ? widget.api.baseUrl.substring(0, widget.api.baseUrl.length - 1)
        : widget.api.baseUrl;
    return '$base$url';
  }

  bool _getBool(String key, bool defaultValue) {
    if (_settings == null) return defaultValue;
    final v = _settings![key];
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return defaultValue;
  }

  Future<void> _openMapPicker() async {
    double lat = 33.5138;
    double lng = 36.2765;
    final latStr = _ctrl('restaurantLat').text.trim();
    final lngStr = _ctrl('restaurantLng').text.trim();
    if (latStr.isNotEmpty && lngStr.isNotEmpty) {
      lat = double.tryParse(latStr.replaceFirst(',', '.')) ?? lat;
      lng = double.tryParse(lngStr.replaceFirst(',', '.')) ?? lng;
      if (lat == 0 && lng == 0) {
        lat = 33.5138;
        lng = 36.2765;
      }
    }
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => AdminMapPickerScreen(initialLat: lat, initialLng: lng),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _ctrl('restaurantLat').text = result.latitude.toString();
      _ctrl('restaurantLng').text = result.longitude.toString();
    });
  }

  Future<void> _save() async {
    final payload = <String, dynamic>{};

    final name = _ctrl('restaurantName').text.trim();
    if (name.isNotEmpty) payload['restaurantName'] = name;

    payload['isManuallyClosed'] = _getBool('isManuallyClosed', false);
    payload['isAcceptingOrders'] = _getBool('isAcceptingOrders', true);

    final closedMsg = _ctrl('closedMessage').text.trim();
    if (closedMsg.isNotEmpty) payload['closedMessage'] = closedMsg;

    final workHours = _ctrl('workHours').text.trim();
    if (workHours.isNotEmpty) payload['workHours'] = workHours;

    final feePerKm = double.tryParse(
        _ctrl('deliveryFeePerKm').text.trim().replaceFirst(',', '.'));
    if (feePerKm != null) payload['deliveryFeePerKm'] = feePerKm;

    final lat = double.tryParse(
        _ctrl('restaurantLat').text.trim().replaceFirst(',', '.'));
    if (lat != null) payload['restaurantLat'] = lat;
    final lng = double.tryParse(
        _ctrl('restaurantLng').text.trim().replaceFirst(',', '.'));
    if (lng != null) payload['restaurantLng'] = lng;

    final phone = _ctrl('supportPhone').text.trim();
    if (phone.isNotEmpty) payload['supportPhone'] = phone;
    final whatsapp = _ctrl('supportWhatsApp').text.trim();
    if (whatsapp.isNotEmpty) payload['supportWhatsApp'] = whatsapp;

    final logo = _ctrl('logoUrl').text.trim();
    if (logo.isNotEmpty) payload['logoUrl'] = logo;

    setState(() => _saving = true);
    try {
      await widget.api.updateSettings(payload);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('AdminApiException:', ''))),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text(
            'هل تريد تسجيل الخروج؟ ستحتاج لإدخال مفتاح الإدارة مرة أخرى.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('خروج')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final storage = AdminAuthStorage();
    await storage.clearAdminKey();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _settings == null) {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section('أساسي', [
            _field('اسم المطعم', 'restaurantName', hint: 'اسم المطعم'),
            _dropdown('حالة المطعم', 'isManuallyClosed',
                items: const ['مفتوح', 'مغلق'], values: const [false, true]),
            _field('رسالة الإغلاق', 'closedMessage',
                hint: 'المطعم مغلق حالياً'),
            _field('أوقات العمل', 'workHours', hint: 'مثال: 10 ص - 12 م'),
          ]),
          _section('التوصيل', [
            _field('سعر التوصيل لكل كم (ل.س)', 'deliveryFeePerKm',
                hint: '0', keyboard: TextInputType.number),
          ]),
          _section('موقع المطعم', [
            OutlinedButton.icon(
              onPressed: _openMapPicker,
              icon: const Icon(Icons.map),
              label: const Text('فتح الخريطة وتحديد الموقع'),
            ),
            const SizedBox(height: 8),
            Text(
              'الموقع الحالي: ${_ctrl('restaurantLat').text.isEmpty ? "—" : "${_ctrl('restaurantLat').text}, ${_ctrl('restaurantLng').text}"}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ]),
          _section('الدعم', [
            _field('رقم الدعم', 'supportPhone'),
            _field('واتساب الدعم', 'supportWhatsApp'),
          ]),
          _section('شعار المطعم', [
            if (_logoPreviewUrl() != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _logoPreviewUrl()!,
                    height: 80,
                    width: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 80),
                  ),
                ),
              ),
            ],
            FilledButton.icon(
              onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
              icon: _uploadingLogo
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate),
              label: Text(_uploadingLogo ? 'جاري الرفع...' : 'اختيار صورة الشعار'),
            ),
            const SizedBox(height: 4),
            Text(
              'اختر صورة من المعرض ثم اضغط حفظ الإعدادات لتطبيق الشعار.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_saving ? 'جاري الحفظ...' : 'حفظ الإعدادات'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج / تغيير المفتاح'),
            onPressed: _logout,
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _field(String label, String key,
      {String? hint, TextInputType? keyboard, int maxLines = 1}) {
    if (!_controllers.containsKey(key)) {
      _controllers[key] = TextEditingController();
      final s = _settings;
      if (s != null) {
        final v = s[key];
        if (v != null)
          _controllers[key]!.text = v is num ? v.toString() : v.toString();
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          TextField(
            controller: _ctrl(key),
            keyboardType: keyboard,
            maxLines: maxLines,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: hint ?? label,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String label, String key,
      {required List<String> items, required List<dynamic> values}) {
    final currentVal = _getBool(key, false);
    final idx = values.indexWhere((v) => v == currentVal);
    final sel = idx >= 0 ? idx : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            value: sel,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: List.generate(items.length,
                (i) => DropdownMenuItem(value: i, child: Text(items[i]))),
            onChanged: (i) {
              if (i == null) return;
              setState(() {
                _settings ??= {};
                _settings![key] = values[i];
              });
            },
          ),
        ],
      ),
    );
  }
}
