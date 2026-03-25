import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BrandState extends ChangeNotifier {
  SharedPreferences? _prefs;

  String restaurantName = '';
  String? logoUrl;
  String primaryColorHex = '#FF6A00';
  String secondaryColorHex = '#111827';
  bool isDarkMode = false;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    restaurantName = prefs.getString('restaurantName') ?? '';
    logoUrl = prefs.getString('logoUrl');
    primaryColorHex = prefs.getString('primaryColor') ?? '#FF6A00';
    secondaryColorHex = prefs.getString('secondaryColor') ?? '#111827';
    isDarkMode = prefs.getBool('driver_isDarkMode') ?? false;
    notifyListeners();
  }

  Future<void> setDarkMode(bool v) async {
    isDarkMode = v;
    await _prefs?.setBool('driver_isDarkMode', v);
    notifyListeners();
  }

  Future<void> toggleTheme() => setDarkMode(!isDarkMode);

  Future<void> setConfig(Map<String, dynamic> s) async {
    restaurantName = (s['restaurantName'] ?? restaurantName).toString();
    logoUrl = s['logoUrl']?.toString() ?? logoUrl;
    primaryColorHex = (s['primaryColor'] ?? s['primaryColorHex'] ?? primaryColorHex).toString();
    secondaryColorHex = (s['secondaryColor'] ?? s['secondaryColorHex'] ?? secondaryColorHex).toString();

    await _prefs?.setString('restaurantName', restaurantName);
    if (logoUrl != null) await _prefs?.setString('logoUrl', logoUrl!);
    await _prefs?.setString('primaryColor', primaryColorHex);
    await _prefs?.setString('secondaryColor', secondaryColorHex);
    notifyListeners();
  }

  Color _parse(String hex, Color fallback) {
    try {
      var h = hex.trim().replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Color get primaryColor => _parse(primaryColorHex, Colors.orange);
}
