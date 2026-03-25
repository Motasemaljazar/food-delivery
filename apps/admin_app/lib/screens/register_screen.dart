import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  static const route = '/register';
  const RegisterScreen({super.key, required this.prefs, required this.state});
  final SharedPreferences prefs;
  final AppState state;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool loading = false;
  String? error;

  Future<Position> _getPos() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if(!enabled) throw Exception('Location services disabled');

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
      throw Exception('Location permission denied');
    }
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> submit() async {
    if(!_formKey.currentState!.validate()) return;
    setState((){ loading=true; error=null; });
    try {
      final pos = await _getPos();
      final api = ApiClient(baseUrl: kBackendBaseUrl);
      final c = await api.registerCustomer(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        lat: pos.latitude,
        lng: pos.longitude,
        address: null,
      );
      await widget.prefs.setInt('customerId', c['id'] as int);
      await widget.prefs.setString('customerName', c['name'] as String);
      await widget.prefs.setString('customerPhone', c['phone'] as String);
      await widget.prefs.setDouble('defaultLat', (c['defaultLat'] as num).toDouble());
      await widget.prefs.setDouble('defaultLng', (c['defaultLng'] as num).toDouble());
      await widget.prefs.setString('defaultAddress', (c['defaultAddress'] ?? '') as String);

      widget.state.setCustomer(id: c['id'] as int, name: c['name'] as String, phone: c['phone'] as String, lat: (c['defaultLat'] as num).toDouble(), lng: (c['defaultLng'] as num).toDouble(), address: c['defaultAddress'] as String?);
      if(mounted) Navigator.of(context).pushReplacementNamed(HomeScreen.route);
    } catch (e) {
      setState(()=>error=e.toString());
    } finally {
      if(mounted) setState(()=>loading=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v)=> (v==null||v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                validator: (v)=> (v==null||v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              if(error!=null) Text(error!, style: const TextStyle(color: Colors.red)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : submit,
                  child: loading ? const CircularProgressIndicator() : const Text('Register & Continue'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
