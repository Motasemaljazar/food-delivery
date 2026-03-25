import 'package:flutter/material.dart';
import '../services/api.dart';
import '../models/app_state.dart';
import '../widgets/brand_title.dart';
import 'location_picker_screen.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key, required this.api, required this.state});
  final ApiClient api;
  final AppState state;

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  bool loading = true;
  String? error;

  List<Map<String, dynamic>> list = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cid = widget.state.customerId;
    if (cid == null) {
      setState(() {
        loading = false;
        error = 'يرجى تسجيل الدخول';
      });
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final res = await widget.api.getAddresses(cid);
      list = res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      widget.state.setSavedAddresses(list);
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() { loading = false; });
    }
  }

  Future<void> _pickLatLng({double? initialLat, double? initialLng, required void Function(double lat, double lng) onPicked}) async {
    final lat0 = initialLat ?? widget.state.defaultLat ?? widget.state.restaurantLat;
    final lng0 = initialLng ?? widget.state.defaultLng ?? widget.state.restaurantLng;
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLat: lat0, initialLng: lng0)),
    );
    if (res is LatLngResult) onPicked(res.lat, res.lng);
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final cid = widget.state.customerId!;
    final title = TextEditingController(text: existing?['title']?.toString() ?? 'البيت');
    final addr = TextEditingController(text: existing?['addressText']?.toString() ?? '');
    final building = TextEditingController(text: existing?['building']?.toString() ?? '');
    final floor = TextEditingController(text: existing?['floor']?.toString() ?? '');
    final apt = TextEditingController(text: existing?['apartment']?.toString() ?? '');
    final notes = TextEditingController(text: existing?['notes']?.toString() ?? '');
    double lat = (existing?['latitude'] as num?)?.toDouble() ?? widget.state.defaultLat ?? widget.state.restaurantLat;
    double lng = (existing?['longitude'] as num?)?.toDouble() ?? widget.state.defaultLng ?? widget.state.restaurantLng;
    bool setDefault = existing == null;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: StatefulBuilder(builder: (ctx, setLocal) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(existing == null ? 'إضافة عنوان' : 'تعديل عنوان', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم العنوان (بيت/عمل...)')),
                  const SizedBox(height: 10),
                  TextField(controller: addr, decoration: const InputDecoration(labelText: 'العنوان النصي'), maxLines: 2),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: building, decoration: const InputDecoration(labelText: 'البناية'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: floor, decoration: const InputDecoration(labelText: 'الطابق'))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: apt, decoration: const InputDecoration(labelText: 'الشقة'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات'), maxLines: 1)),
                  ]),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _pickLatLng(initialLat: lat, initialLng: lng, onPicked: (a,b){ setLocal((){ lat=a; lng=b; }); }),
                    icon: const Icon(Icons.map_outlined),
                    label: Text('تحديد الموقع على الخريطة (${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: setDefault,
                    onChanged: (v) => setLocal(() => setDefault = v),
                    title: const Text('اجعل هذا العنوان افتراضي'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('حفظ'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }),
        );
      },
    );

    if (ok != true) return;

    try {
      if (existing == null) {
        await widget.api.createAddress({
          'customerId': cid,
          'title': title.text.trim(),
          'addressText': addr.text.trim(),
          'latitude': lat,
          'longitude': lng,
          'building': building.text.trim().isEmpty ? null : building.text.trim(),
          'floor': floor.text.trim().isEmpty ? null : floor.text.trim(),
          'apartment': apt.text.trim().isEmpty ? null : apt.text.trim(),
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
          'setDefault': setDefault,
        });
      } else {
        await widget.api.updateAddress((existing['id'] as num).toInt(), {
          'customerId': cid,
          'title': title.text.trim(),
          'addressText': addr.text.trim(),
          'latitude': lat,
          'longitude': lng,
          'building': building.text.trim().isEmpty ? null : building.text.trim(),
          'floor': floor.text.trim().isEmpty ? null : floor.text.trim(),
          'apartment': apt.text.trim().isEmpty ? null : apt.text.trim(),
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        });
        if (setDefault) {
          await widget.api.setDefaultAddress((existing['id'] as num).toInt(), cid);
        }
      }
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    }
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final cid = widget.state.customerId!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العنوان'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteAddress((a['id'] as num).toInt(), cid);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: BrandTitle(state: widget.state, suffix: 'عناويني'),
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openEditor(),
          child: const Icon(Icons.add),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : (error != null)
                ? Center(child: Text(error!))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (ctx, i) {
                      final a = list[i];
                      final id = (a['id'] as num?)?.toInt() ?? 0;
                      final isDef = a['isDefault'] == true;
                      final title = (a['title'] ?? '').toString();
                      final address = (a['addressText'] ?? '').toString();
                      return Card(
                        child: ListTile(
                          leading: Icon(isDef ? Icons.star : Icons.location_on_outlined),
                          title: Text(title.isEmpty ? 'عنوان' : title),
                          subtitle: Text(address),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'default') {
                                await widget.api.setDefaultAddress(id, widget.state.customerId!);
                                await _load();
                              } else if (v == 'edit') {
                                await _openEditor(existing: a);
                              } else if (v == 'delete') {
                                await _delete(a);
                              } else if (v == 'use') {
                                widget.state.selectAddress(a);
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم اختيار العنوان')));
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'use', child: Text('استخدم للطلب القادم')),
                              const PopupMenuItem(value: 'default', child: Text('اجعله افتراضي')),
                              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                              const PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                          onTap: () {
                            widget.state.selectAddress(a);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم اختيار العنوان')));
                          },
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: list.length,
                  ),
      ),
    );
  }
}
