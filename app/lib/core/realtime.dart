import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'auth/auth_controller.dart';
import 'config.dart';

class RealtimeEvent {
  RealtimeEvent(this.name, this.data);
  final String name;
  final Map<String, dynamic> data;
}

/// One Socket.IO connection while signed in. Screens listen to [events] and join a thread's room while open.
class RealtimeClient {
  RealtimeClient(String token, String baseUrl) {
    _socket = io.io(baseUrl, io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token}).enableReconnection().build());
    for (final e in const ['message.created', 'task.transcribed', 'task.structured', 'task.updated']) {
      _socket.on(e, (d) { if (d is Map) _events.add(RealtimeEvent(e, Map<String, dynamic>.from(d))); });
    }
    _socket.onConnect((_) { for (final t in _joined) { _socket.emit('thread.join', t); } _reconnects.add(null); });
  }

  late final io.Socket _socket;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _reconnects = StreamController<void>.broadcast();
  final _joined = <String>{};

  Stream<RealtimeEvent> get events => _events.stream;
  /// Fires on every (re)connect: a good moment to flush the outbox and refresh.
  Stream<void> get connected => _reconnects.stream;

  void join(String threadId) { _joined.add(threadId); _socket.emit('thread.join', threadId); }
  void leave(String threadId) { _joined.remove(threadId); _socket.emit('thread.leave', threadId); }

  void dispose() {
    _socket.dispose();
    _events.close();
    _reconnects.close();
  }
}

final realtimeProvider = FutureProvider<RealtimeClient?>((ref) async {
  final user = ref.watch(authProvider).value;
  if (user == null) return null;
  final tokens = await ref.read(tokenStoreProvider).read();
  if (tokens == null) return null;
  final client = RealtimeClient(tokens.access, ref.watch(serverUrlProvider));
  ref.onDispose(client.dispose);
  return client;
});
