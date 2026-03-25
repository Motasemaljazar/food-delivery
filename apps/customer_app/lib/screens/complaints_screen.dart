import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/api.dart';

/// NOTE: Kept the file/name for backward compatibility.
/// This is now the *real chat* between the customer and the restaurant/admin.
class ComplaintsScreen extends StatefulWidget {
  const ComplaintsScreen({super.key, required this.api, required this.state});
  final ApiClient api;
  final AppState state;

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  bool loading = true;
  String? error;
  int? threadId;
  bool isChatBlocked = false;
  Map<String, dynamic>? thread;

  final msgC = TextEditingController();
  final _scroll = ScrollController();
  int _lastSeq = 0;
  final Set<int> _seenIds = <int>{};

  @override
  void initState() {
    super.initState();
    _lastSeq = widget.state.complaintMessageSeq;
    widget.state.addListener(_onRealtime);
    _load();
  }

  void _onRealtime() {
    if (!mounted) return;
    if (widget.state.complaintMessageSeq == _lastSeq) return;
    _lastSeq = widget.state.complaintMessageSeq;

    final p = widget.state.lastComplaintMessage;
    if (p == null) return;
    final tid = p['threadId'];
    if (threadId == null || tid != threadId) return;

    final msgs = (thread?['messages'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .toList();

    final incomingId = (p['id'] as num?)?.toInt() ?? 0;
    if (incomingId > 0) {
      if (_seenIds.contains(incomingId)) return;
      _seenIds.add(incomingId);
    } else {
      // Fallback: skip exact consecutive duplicates (reconnect edge cases)
      if (msgs.isNotEmpty) {
        final last = msgs.last;
        final lastFromAdmin = last['fromAdmin'] == true;
        final lastText = (last['message'] ?? '').toString();
        final incomingFromAdmin = p['fromAdmin'] == true;
        final incomingText = (p['message'] ?? '').toString();
        if (lastFromAdmin == incomingFromAdmin && lastText == incomingText)
          return;
      }
    }

    msgs.add({
      'id': incomingId,
      'fromAdmin': p['fromAdmin'] == true,
      'message': (p['message'] ?? '').toString(),
      'createdAtUtc':
          (p['createdAtUtc'] ?? DateTime.now().toUtc().toIso8601String())
              .toString(),
    });

    setState(() {
      thread = {...(thread ?? {}), 'messages': msgs};
    });
    _scrollToBottom();
  }

  Future<void> _scrollToBottom() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _load() async {
    final customerId = widget.state.customerId;
    if (customerId == null) {
      setState(() {
        loading = false;
        error = 'يجب تسجيل الدخول أولاً';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final info = await widget.api.getOrCreateChatThread(customerId);
      threadId = (info['threadId'] as num).toInt();
      isChatBlocked = info['isChatBlocked'] == true;
      widget.state.setOpenComplaintThread(threadId);
      thread = await widget.api.getComplaint(threadId!);
      // Build de-dup set from current history
      _seenIds
        ..clear()
        ..addAll(((thread?['messages'] as List<dynamic>? ?? const [])
            .map((e) => (e as Map)['id'])
            .where((x) => x is int)
            .cast<int>()));
      // keep in state for badges
      widget.state.setComplaintThreads([
        {
          'id': threadId,
          'title': 'دردشة مع المطعم',
          'unreadCount': 0,
          'lastMessagePreview': '',
        }
      ]);
      await _scrollToBottom();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _send() async {
    final txt = msgC.text.trim();
    if (txt.isEmpty) return;
    if (threadId == null) return;
    if (isChatBlocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا يمكنك إرسال رسائل حالياً (تم إيقاف الدردشة)')),
      );
      return;
    }

    try {
      await widget.api
          .sendComplaintMessage(threadId!, fromAdmin: false, message: txt);
      msgC.clear();
      // No optimistic append to avoid duplicates. Server will push the message via SignalR.
      // (In poor connectivity scenarios, the message will appear once the push arrives.)
      setState(() {});
    } catch (e) {
      final s = e.toString();
      if (s.contains('chat_blocked')) {
        setState(() => isChatBlocked = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إيقاف الدردشة من قبل الإدارة')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل الإرسال: $s')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    widget.state.setOpenComplaintThread(null);
    widget.state.removeListener(_onRealtime);
    msgC.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (msgDay == today) return timeStr;
      if (msgDay == today.subtract(const Duration(days: 1))) return 'أمس $timeStr';
      return '${dt.day}/${dt.month} $timeStr';
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (loading) {
      final w = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text('جاري تحميل المحادثة…', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      );
      return (Scaffold.maybeOf(context) == null) ? Scaffold(body: w) : w;
    }
    if (error != null) {
      final w = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
      return (Scaffold.maybeOf(context) == null) ? Scaffold(body: w) : w;
    }

    final msgs = (thread?['messages'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    final content = Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: cs.surface,
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.support_agent_rounded, color: cs.onPrimaryContainer, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الدردشة مع الإدارة',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isChatBlocked ? 'الدردشة موقوفة' : 'نحن هنا لمساعدتك',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: 'تحديث',
                  onPressed: _load,
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHighest,
                    foregroundColor: cs.primary,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        ),

        if (isChatBlocked)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: cs.onErrorContainer, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'تم إيقاف الدردشة من قبل الإدارة. يمكنك تصفح التطبيق بشكل طبيعي لكن لا يمكنك إرسال رسائل حالياً.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                        height: 1.35,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            itemCount: msgs.isEmpty ? 1 : msgs.length,
            itemBuilder: (context, i) {
              if (msgs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.chat_bubble_outline_rounded, size: 56, color: cs.primary.withOpacity(0.7)),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'ابدأ المحادثة مع المطعم',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'اطرح استفسارك أو تواصل مع الإدارة وسنرد في أقرب وقت',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              }

              final m = msgs[i];
              final fromAdmin = m['fromAdmin'] == true;
              final text = (m['message'] ?? '').toString();
              final timeStr = _formatTime(m['createdAtUtc']?.toString());

              // RTL: user (me) on right = start, admin on left = end
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: fromAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: fromAdmin ? cs.surfaceContainerHighest : cs.primaryContainer,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(fromAdmin ? 4 : 18),
                            bottomRight: Radius.circular(fromAdmin ? 18 : 4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              text,
                              textDirection: TextDirection.rtl,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: fromAdmin ? cs.onSurface : cs.onPrimaryContainer,
                                height: 1.4,
                              ),
                            ),
                            if (timeStr.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                timeStr,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: (fromAdmin ? cs.onSurfaceVariant : cs.onPrimaryContainer).withOpacity(0.8),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (fromAdmin)
                      Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.storefront_rounded, size: 18, color: cs.primary),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              );
            },
          ),
        ),

        // Input area
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
            color: cs.surface,
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: msgC,
                    textDirection: TextDirection.rtl,
                    enabled: !isChatBlocked,
                    decoration: InputDecoration(
                      hintText: isChatBlocked ? 'الدردشة موقوفة' : 'اكتب رسالتك…',
                      hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.7)),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withOpacity(0.6),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: cs.primary, width: 1.5),
                      ),
                    ),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isChatBlocked ? null : _send,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: isChatBlocked ? cs.surfaceContainerHighest : cs.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: isChatBlocked ? null : [
                          BoxShadow(
                            color: cs.primary.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.send_rounded,
                        color: isChatBlocked ? cs.onSurfaceVariant : cs.onPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (Scaffold.maybeOf(context) == null) {
      return Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        appBar: AppBar(
          title: const Text('الدردشة'),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0.5,
        ),
        body: content,
      );
    }
    return content;
  }
}
