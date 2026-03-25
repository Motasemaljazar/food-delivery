import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartItem {
  CartItem({
    required this.key,
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.qty,
    required this.optionsSnapshot,
    required this.optionsLabel,
  });
  final String key;
  final int productId;
  final String name;
  final double unitPrice;
  int qty;
  final String optionsSnapshot; // JSON string
  final String optionsLabel; // human readable

  double get total => unitPrice * qty;
}

class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;
  bool isDarkMode = false;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    isDarkMode = prefs.getBool('theme_dark') ?? false;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    isDarkMode = value;
    await _prefs?.setBool('theme_dark', value);
    notifyListeners();
  }

  Future<void> toggleTheme() => setDarkMode(!isDarkMode);
  // App branding/config (from /api/public/app-config)
  String restaurantName = 'مطعم';
  String? logoUrl;
  String? customerSplashUrl;
  List<String> splashBackgrounds = const [];
  String primaryColorHex = '#FF6A00';
  String secondaryColorHex = '#111827';
  String workHours = '';
  double minOrderAmount = 0;
  double deliveryFeeValue = 0;
  String supportPhone = '';
  String supportWhatsApp = '';
  bool isAcceptingOrders = true;
  String closedMessage = 'المطعم مغلق حالياً';
  double restaurantLat = 0;
  double restaurantLng = 0;

  List<dynamic> notifications = const [];
  int unreadNotifications = 0;

  // Menu cache
  List<dynamic> menuCategories = const [];
  List<dynamic> activeOffers = const [];

  void setMenu(Map<String, dynamic> menu) {
    menuCategories = (menu['categories'] is List) ? (menu['categories'] as List) : const [];
    activeOffers = (menu['offers'] is List) ? (menu['offers'] as List) : const [];
    notifyListeners();
  }

  // Realtime order ETA cache (orderId -> payload)
  final Map<int, Map<String, dynamic>> orderEtaCache = {};

  void upsertOrderEta(Map<String, dynamic> payload) {
    final oid = payload['orderId'];
    if (oid is int) {
      orderEtaCache[oid] = Map<String, dynamic>.from(payload);
      notifyListeners();
    }
  }

  void setConfig(Map<String, dynamic> s) {
    restaurantName = (s['restaurantName'] ?? restaurantName).toString();
    logoUrl = s['logoUrl']?.toString();
    final splashUrls = (s['splashUrls'] is Map) ? (s['splashUrls'] as Map) : null;
    customerSplashUrl = splashUrls?['customer']?.toString() ?? s['customerSplashUrl']?.toString();
    splashBackgrounds = (s['splashBackgrounds'] is List) ? (s['splashBackgrounds'] as List).map((e) => e.toString()).toList() : splashBackgrounds;
    primaryColorHex = (s['primaryColor'] ?? s['primaryColorHex'] ?? primaryColorHex).toString();
    secondaryColorHex = (s['secondaryColor'] ?? s['secondaryColorHex'] ?? secondaryColorHex).toString();
    workHours = (s['openHours'] ?? s['workHours'] ?? workHours).toString();
    minOrderAmount = (s['minOrder'] is num) ? (s['minOrder'] as num).toDouble() : ((s['minOrderAmount'] is num) ? (s['minOrderAmount'] as num).toDouble() : minOrderAmount);
    deliveryFeeValue = (s['deliveryFee'] is num) ? (s['deliveryFee'] as num).toDouble() : ((s['deliveryFeeValue'] is num) ? (s['deliveryFeeValue'] as num).toDouble() : deliveryFeeValue);
    supportPhone = (s['supportPhone'] ?? supportPhone).toString();
    supportWhatsApp = (s['whatsapp'] ?? s['supportWhatsApp'] ?? supportWhatsApp).toString();
    isAcceptingOrders = (s['acceptOrders'] == true) || (s['isAcceptingOrders'] == true);
    closedMessage = (s['texts'] is Map && (s['texts'] as Map)['closedMessage'] != null)
        ? (s['texts'] as Map)['closedMessage'].toString()
        : (s['closedMessage']?.toString() ?? closedMessage);
    restaurantLat = (s['restaurantLat'] is num) ? (s['restaurantLat'] as num).toDouble() : restaurantLat;
    restaurantLng = (s['restaurantLng'] is num) ? (s['restaurantLng'] as num).toDouble() : restaurantLng;
    notifyListeners();
  }

  void setNotifications(List<dynamic> list) {
    notifications = list;
    unreadNotifications = list.where((n) => (n is Map) && (n['isRead'] != true)).length;
    notifyListeners();
  }

  void pushNotification(dynamic n) {
    notifications = [n, ...notifications];
    unreadNotifications = notifications.where((x) => (x is Map) && (x['isRead'] != true)).length;
    notifyListeners();
  }
  int? customerId;
  String? customerName;
  String? customerPhone;
  double? defaultLat;
  double? defaultLng;
  String? defaultAddress;

  void setDeliveryLocation({required double lat, required double lng, String? address}) {
    defaultLat = lat;
    defaultLng = lng;
    defaultAddress = address;
    notifyListeners();
  }

  final List<CartItem> cart = [];

  void setCustomer({required int id, required String name, required String phone, required double lat, required double lng, String? address}) {
    customerId = id;
    customerName = name;
    customerPhone = phone;
    defaultLat = lat;
    defaultLng = lng;
    defaultAddress = address;
    notifyListeners();
  }

  void addToCartBasic({required int productId, required String name, required double basePrice}) {
    addToCartWithOptions(
      productId: productId,
      name: name,
      unitPrice: basePrice,
      optionsSnapshot: '{"variantId":null,"addonIds":[],"note":null}',
      optionsLabel: 'بدون إضافات',
    );
  }

  void addToCartWithOptions({
    required int productId,
    required String name,
    required double unitPrice,
    required String optionsSnapshot,
    required String optionsLabel,
  }) {
    final key = '$productId|$optionsSnapshot';
    final existing = cart.where((c) => c.key == key).toList();
    if (existing.isNotEmpty) {
      existing.first.qty += 1;
    } else {
      cart.add(CartItem(
        key: key,
        productId: productId,
        name: name,
        unitPrice: unitPrice,
        qty: 1,
        optionsSnapshot: optionsSnapshot,
        optionsLabel: optionsLabel,
      ));
    }
    notifyListeners();
  }

  void removeFromCart(String key) {
    cart.removeWhere((c) => c.key == key);
    notifyListeners();
  }

  void setQty(String key, int qty) {
    final it = cart.firstWhere((c) => c.key == key);
    it.qty = qty.clamp(1, 999);
    notifyListeners();
  }

  double get cartSubtotal => cart.fold(0, (s, it) => s + it.total);

  void clearCart() {
    cart.clear();
    notifyListeners();
  }
}
