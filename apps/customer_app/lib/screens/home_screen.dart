import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../models/app_state.dart';
import '../services/api.dart';
import '../services/app_refs.dart';
import 'orders_screen.dart';
import 'cart_screen.dart';
import 'menu_screen.dart';
import 'complaints_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';
import 'blocked_screen.dart';
import '../widgets/brand_title.dart';
import 'closed_screen.dart';
import '../services/realtime.dart';

class HomeScreen extends StatefulWidget {
  static const route = '/home';
  const HomeScreen({super.key, required this.prefs, required this.state});
  final SharedPreferences prefs;
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int idx = 0;
  late final ApiClient api;
  late final RealtimeClient rt;
  bool _ratingDialogOpen = false;
  // منع تكرار عرض رسائل الـ SnackBar عند استقبال نفس الحدث أكثر من مرة
  bool _handlingAppBlock = false;
  bool _appUnblockSnackBarShown = false;
  bool _chatBlockedSnackBarShown = false;
  DateTime? _lastAdminMessageSnackBarAt;

  @override
  void initState() {
    super.initState();
    api = ApiClient(baseUrl: kBackendBaseUrl);
    AppRefs.api = api;
    rt = RealtimeClient(baseUrl: kBackendBaseUrl);
    _connectRealtime();
  }

  Future<void> _connectRealtime() async {
    final id = widget.state.customerId;
    if (id == null) return;
    await rt.connectCustomer(
      customerId: id,
      onNotification: (n) => widget.state.pushNotification(n),
      onOrderStatus: (p) {
        final status = (p['status'] ?? '').toString();
        if (status == 'Delivered' || status == 'delivered' || status == '5') {
          _checkPendingRating();
        }
      },
      onOrderEta: (p) { widget.state.upsertOrderEta(p); },
      onComplaintMessage: (p) {
        widget.state.applyComplaintMessage(p);
        final fromAdmin = p['fromAdmin'] == true;
        final threadId = p['threadId'];
        if (fromAdmin && mounted && widget.state.openComplaintThreadId != threadId) {
          final now = DateTime.now();
          if (_lastAdminMessageSnackBarAt != null && now.difference(_lastAdminMessageSnackBarAt!).inSeconds < 4) return;
          _lastAdminMessageSnackBarAt = now;
          try { SystemSound.play(SystemSoundType.alert); } catch (_) {}
          final msg = (p['message'] ?? '').toString();
          final shortMsg = msg.length > 40 ? (msg.substring(0, 40) + '…') : msg;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('رسالة جديدة من الإدارة: $shortMsg'),
              action: SnackBarAction(
                label: 'فتح',
                onPressed: () { setState(() => idx = 3); },
              ),
            ),
          );
        }
      },
      onChatBlocked: (p) {
        final blocked = p['isChatBlocked'] == true;
        if (blocked && mounted && !_chatBlockedSnackBarShown) {
          _chatBlockedSnackBarShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إيقاف الدردشة من قبل الإدارة')),
          );
          Future.delayed(const Duration(seconds: 10), () { if (mounted) _chatBlockedSnackBarShown = false; });
        }
      },
      onSettingsUpdated: (s) async {
        widget.state.setConfig(s);
        try { await widget.prefs.setString('cached_settings', jsonEncode(s)); } catch (_) {}
      },
      onNotificationRefresh: () async {
        try {
          final list = await api.listNotifications(id);
          widget.state.setNotifications(list);
        } catch (_) {}
      },
      // ✅ معالج حدث الإيقاف من التطبيق (عرض الرسالة مرة واحدة فقط)
      onAppBlocked: (p) async {
        final blocked = p['isAppBlocked'] == true;
        final customerId = p['customerId'];

        if (blocked && customerId == id && mounted) {
          if (_handlingAppBlock) return;
          _handlingAppBlock = true;
          await rt.disconnect();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إيقاف حسابك من قبل الإدارة'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => BlockedScreen(
                prefs: widget.prefs,
                state: widget.state,
              ),
            ),
            (route) => false,
          );
        } else if (!blocked && customerId == id && mounted && !_appUnblockSnackBarShown) {
          _appUnblockSnackBarShown = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إلغاء إيقاف حسابك، يمكنك الآن استخدام التطبيق'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          Future.delayed(const Duration(seconds: 15), () { if (mounted) _appUnblockSnackBarShown = false; });
        }
      },
      onAccountDeleted: (p) async {
        final deletedId = (p['customerId'] is num) ? (p['customerId'] as num).toInt() : null;
        if (deletedId != id || !mounted) return;
        await rt.disconnect();
        if (!mounted) return;
        widget.state.clearCustomer();
        await widget.prefs.remove('customerId');
        await widget.prefs.remove('customerName');
        await widget.prefs.remove('customerPhone');
        await widget.prefs.remove('defaultLat');
        await widget.prefs.remove('defaultLng');
        await widget.prefs.remove('defaultAddress');
        try { await FirebaseAuth.instance.signOut(); } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف حسابك من قبل الإدارة'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => AuthScreen(prefs: widget.prefs, state: widget.state)),
          (route) => false,
        );
      },
    );

    // Also check on every connect (e.g. app start)
    _checkPendingRating();
  }

  Future<void> _checkPendingRating() async {
    if (!mounted) return;
    if (_ratingDialogOpen) return;
    final customerId = widget.state.customerId;
    if (customerId == null) return;
    try {
      final res = await api.getPendingRating(customerId);
      if (!mounted) return;
      if (res['hasPending'] == true && res['orderId'] is int) {
        final hasDriver = res['hasDriver'] == true;
        final oid = res['orderId'] as int;
        if (widget.state.isRatingDismissed(oid)) return;
        if (_snoozedOrderId == oid) return;
        await _showOptionalRatingDialog(orderId: oid, hasDriver: hasDriver);
      }
    } catch (_) {
      // ignore
    }
  }

  int? _snoozedOrderId;

  Future<void> _showOptionalRatingDialog({required int orderId, required bool hasDriver}) async {
    if (!mounted) return;
    _ratingDialogOpen = true;
    int restaurantStars = 5;
    int driverStars = 5;
    final comment = TextEditingController();

    Widget starRow(int value, void Function(int) setValue, ColorScheme cs) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) {
          final s = i + 1;
          return IconButton(
            onPressed: () => setValue(s),
            icon: Icon(
              s <= value ? Icons.star_rounded : Icons.star_border_rounded,
              color: s <= value ? cs.secondary : cs.onSurfaceVariant.withOpacity(0.5),
              size: 36,
            ),
          );
        }),
      );
    }

    bool sending = false;
    bool closedByX = false;
    bool closedByLater = false;

    void closeDialog(BuildContext dialogCtx) {
      try {
        Navigator.of(dialogCtx, rootNavigator: true).pop();
        return;
      } catch (_) {}
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: cs.surface,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 44, 20, 16),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.star_rounded, color: cs.primary, size: 26),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('تقييم الطلب', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.onSurface)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('ساعدنا بتقييم الخدمة لتحسين الجودة. (اختياري)', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 18),
                          Text('تقييم المطعم', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                          const SizedBox(height: 6),
                          starRow(restaurantStars, (v) => setState(() => restaurantStars = v), cs),
                          const SizedBox(height: 14),
                          TextField(
                            controller: comment,
                            decoration: InputDecoration(
                              hintText: 'اكتب تعليقك (اختياري)',
                              filled: true,
                              fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            maxLines: 3,
                            textDirection: TextDirection.rtl,
                          ),
                          if (hasDriver) ...[
                            const SizedBox(height: 14),
                            Text('تقييم السائق', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            const SizedBox(height: 6),
                            starRow(driverStars, (v) => setState(() => driverStars = v), cs),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: sending
                                  ? null
                                  : () {
                                      if (sending) return;
                                      if (!ctx.mounted) return;
                                      sending = true;
                                      closeDialog(ctx);
                                      Future.microtask(() async {
                                        try {
                                          final cid = widget.state.customerId;
                                          if (cid == null) return;
                                          await api.submitOrderRating(
                                            orderId: orderId,
                                            customerId: cid,
                                            restaurantRate: restaurantStars,
                                            driverRate: hasDriver ? driverStars : 5,
                                            comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
                                          );
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التقييم ✅')));
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ التقييم: $e')));
                                        }
                                      });
                                    },
                              icon: const Icon(Icons.check_circle_outline, size: 22),
                              label: const Text('إرسال التقييم'),
                              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              closedByLater = true;
                              closeDialog(ctx);
                            },
                            child: Text('لاحقاً', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () {
                        closedByX = true;
                        widget.state.markRatingDismissed(orderId);
                        closeDialog(ctx);
                      },
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHighest),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );

    comment.dispose();
    _ratingDialogOpen = false;

    if (closedByX) {
      // لا تُعرض مرة أخرى لهذا الطلب (تم الحفظ في markRatingDismissed)
    } else if (closedByLater) {
      _snoozedOrderId = orderId;
    } else {
      Future.microtask(_checkPendingRating);
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _connectRealtime();
  }

  @override
  void dispose() {
    rt.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.state.isAcceptingOrders) {
      return AnimatedBuilder(
        animation: widget.state,
        builder: (_, __) => Scaffold(
          appBar: AppBar(title: BrandTitle(state: widget.state, suffix: 'مغلق')),
          body: ClosedScreen(state: widget.state),
        ),
      );
    }

    final pages = [
      MenuScreen(api: api, state: widget.state),
      CartScreen(api: api, state: widget.state),
      OrdersScreen(api: api, state: widget.state),
      ComplaintsScreen(api: api, state: widget.state),
      ProfileScreen(state: widget.state, prefs: widget.prefs, api: api),
    ];

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: widget.state,
      builder: (_, __) => Scaffold(
        appBar: AppBar(
          title: Align(
            alignment: Alignment.centerRight,
            child: BrandTitle(
              state: widget.state,
              suffix: 'أهلاً ${widget.state.customerName ?? ''}',
              logoSize: 40,
            ),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'الإشعارات',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsScreen(api: api, state: widget.state))),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.notifications_outlined, color: theme.appBarTheme.foregroundColor),
                  if (widget.state.unreadNotifications > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.appBarTheme.backgroundColor ?? Colors.white, width: 1),
                        ),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Center(
                          child: Text(
                            widget.state.unreadNotifications > 99 ? '99+' : '${widget.state.unreadNotifications}',
                            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ),
                    )
                ],
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            pages[idx],
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: NavigationBar(
                selectedIndex: idx,
                onDestinationSelected: (v) => setState(() => idx = v),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.restaurant_menu_rounded),
                    selectedIcon: Icon(Icons.restaurant_menu_rounded),
                    label: 'القائمة',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.shopping_cart_outlined),
                    selectedIcon: Icon(Icons.shopping_cart_rounded),
                    label: 'السلة',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long_rounded),
                    label: 'طلباتي',
                  ),
                  NavigationDestination(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.support_agent_outlined),
                        if (widget.state.unreadComplaints > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: primary,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Center(
                                child: Text(
                                  widget.state.unreadComplaints > 99 ? '99+' : '${widget.state.unreadComplaints}',
                                  style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontSize: 9),
                                ),
                              ),
                            ),
                          )
                      ],
                    ),
                    selectedIcon: const Icon(Icons.support_agent_rounded),
                    label: 'الدردشة',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'حسابي',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
