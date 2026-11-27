import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../data/providers.dart';
import '../../main.dart';

/// Push (spec §10.5): register the token after sign-in and on refresh; a tap opens the thread; one notification per thread.
/// Without Firebase config files (google-services.json / GoogleService-Info.plist) this quietly does nothing; see docs/SETUP.md.
final pushProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(authProvider).value;
  if (user == null || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Push off: Firebase is not configured ($e)');
    return;
  }
  final fm = FirebaseMessaging.instance;
  await fm.requestPermission();
  final repo = ref.read(repositoryProvider);
  final platform = Platform.isIOS ? 'ios' : 'android';
  // ponytail: getToken/onTokenRefresh still work; move to register()/onRegistered when the Firebase files arrive and push is tested.
  // ignore: deprecated_member_use
  final token = await fm.getToken();
  if (token != null) await repo.registerDevice(token, platform);
  // ignore: deprecated_member_use
  final refreshSub = fm.onTokenRefresh.listen((t) => repo.registerDevice(t, platform));

  void open(RemoteMessage m) {
    final taskId = m.data['taskId'], threadId = m.data['threadId'];
    if (taskId is String) { ref.read(routerProvider).push('/case/$taskId'); } else if (threadId is String) { ref.read(routerProvider).push('/chat/$threadId'); }
  }
  final initial = await fm.getInitialMessage();
  if (initial != null) open(initial);
  final openedSub = FirebaseMessaging.onMessageOpenedApp.listen(open);

  // In the foreground the system shows nothing, so show it ourselves, tagged by thread so they group.
  final local = FlutterLocalNotificationsPlugin();
  await local.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings()),
    onDidReceiveNotificationResponse: (r) { if (r.payload != null) ref.read(routerProvider).push('/chat/${r.payload}'); },
  );
  final fgSub = FirebaseMessaging.onMessage.listen((m) {
    final n = m.notification, threadId = m.data['threadId'] as String?;
    if (n == null || threadId == null) return;
    local.show(
      id: threadId.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails('tasks', 'Tasks', importance: Importance.high, tag: threadId, groupKey: threadId),
        iOS: DarwinNotificationDetails(threadIdentifier: threadId),
      ),
      payload: threadId,
    );
  });
  ref.onDispose(() { refreshSub.cancel(); openedSub.cancel(); fgSub.cancel(); });
});
