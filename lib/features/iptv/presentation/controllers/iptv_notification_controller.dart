import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data/providers.dart';
import '../../../../core/domain/models.dart';
import '../widgets/iptv_sync_result_sheet.dart';
import 'iptv_sync_controller.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Tracks popups on the root navigator, including PIN and confirmation sheets.
class IptvNotificationRouteObserver extends NavigatorObserver {
  final Set<Route<dynamic>> _popups = {};
  bool get hasPopup => _popups.isNotEmpty;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _popups.add(route);
  }
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _popups.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _popups.remove(route);
}
final iptvNotificationRouteObserver = IptvNotificationRouteObserver();

/// Firestore is the single completion inbox. FCM only opens a source; it never
/// races another listener to acknowledge or display the same completion sheet.
class IptvNotificationController with WidgetsBindingObserver {
  IptvNotificationController(this._ref);
  final Ref _ref;
  StreamSubscription? _notificationsSub;
  StreamSubscription? _fcmOpenSub;
  StreamSubscription? _tokenRefreshSub;
  Timer? _timer;
  final Map<String, Map<String, dynamic>> _pending = {};
  final Set<String> _shown = {};
  String? _uid;
  String? _pendingSource;
  bool _showing = false;
  bool _disposed = false;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _ref.listen<AsyncValue<Account?>>(accountProvider, (previous, next) {
      final account = next.asData?.value;
      if (account?.uid == _uid) return;
      _bindUser(account?.uid);
    });
    _bindUser(_ref.read(accountProvider).asData?.value?.uid);
  }

  void _bindUser(String? uid) {
    _notificationsSub?.cancel();
    _fcmOpenSub?.cancel();
    _tokenRefreshSub?.cancel();
    _timer?.cancel();
    _pending.clear();
    _shown.clear();
    _pendingSource = null;
    _uid = uid;
    if (uid == null || !_ref.read(repositoryProvider).configured) return;
    _notificationsSub = _ref.read(iptvRepositoryProvider).watchPendingNotifications(uid).listen((events) {
      if (_disposed || _uid != uid) return;
      for (final event in events) {
        final id = event['jobId'] as String?;
        if (id != null && !_shown.contains(id)) _pending[id] = event;
      }
      _scheduleDrain();
    }, onError: (Object _) { /* Persistent inbox is retried after session recovery. */ });
    unawaited(_setupFcm(uid));
  }

  bool get _foreground => WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _scheduleDrain() {
    if (_disposed || _timer != null || (_pending.isEmpty && _pendingSource == null)) return;
    _timer = Timer(const Duration(milliseconds: 600), () {
      _timer = null;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_disposed || _showing || !_foreground || _uid == null) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) { _scheduleDrain(); return; }
    final path = GoRouter.of(context).routeInformationProvider.value.uri.path;
    if (iptvNotificationRouteObserver.hasPopup || path.endsWith('/add') ||
        path.endsWith('/edit') || path == '/login' || path == '/loading' ||
        path.contains('/scan') || MediaQuery.viewInsetsOf(context).bottom > 0) {
      _scheduleDrain(); return;
    }
    if (_pendingSource != null) {
      final id = _pendingSource!;
      _pendingSource = null;
      context.push('/iptv/${Uri.encodeComponent(id)}');
      _scheduleDrain(); return;
    }
    if (_pending.isEmpty) return;
    final uid = _uid!;
    final entry = _pending.entries.first;
    final event = entry.value;
    final repo = _ref.read(iptvRepositoryProvider);
    final sourceId = event['sourceId'] as String? ?? '';
    _showing = true;
    try {
      await IptvSyncResultSheet.show(context, jobId: entry.key, sourceId: sourceId,
        sourceName: event['sourceName'] as String? ?? 'IPTV',
        isSuccess: event['status'] == 'completed', errorCode: event['errorCode'] as String?,
        onRetry: event['status'] == 'completed' ? null : () async {
          try { await repo.triggerSync(sourceId); } catch (_) { /* Source page retains backend error state. */ }
        });
      if (!_disposed && _uid == uid) {
        _shown.add(entry.key);
        _pending.remove(entry.key);
        await repo.markNotificationDelivered(uid, entry.key);
      }
    } catch (_) {
      // Keep backend event pending after interrupted delivery or connectivity loss.
    } finally {
      _showing = false;
      _scheduleDrain();
    }
  }

  Future<void> _setupFcm(String uid) async {
    if (kIsWeb || Firebase.apps.isEmpty) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (_disposed || _uid != uid) return;
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) { return; }
      _tokenRefreshSub = messaging.onRegistered.listen((token) async {
        if (_disposed || _uid != uid) return;
        try { await _ref.read(iptvRepositoryProvider).registerFcmToken(uid, token); } catch (_) {}
      });
      await messaging.register();
      if (_disposed || _uid != uid) return;
      _fcmOpenSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationClick);
      final initial = await messaging.getInitialMessage();
      if (!_disposed && _uid == uid && initial != null) _handleNotificationClick(initial);
    } catch (_) { /* Persistent completion inbox also works without APNs/FCM. */ }
  }

  void _handleNotificationClick(RemoteMessage message) {
    if (message.data['recipientUid'] != _uid) return;
    final source = message.data['sourceId'] as String?;
    if (source == null || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(source)) return;
    _pendingSource = source;
    _scheduleDrain();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleDrain();
  }
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _notificationsSub?.cancel();
    _fcmOpenSub?.cancel();
    _tokenRefreshSub?.cancel();
    _timer?.cancel();
  }
}

final iptvNotificationControllerProvider = Provider<IptvNotificationController>((ref) {
  final controller = IptvNotificationController(ref)..initialize();
  ref.onDispose(controller.dispose);
  return controller;
});
