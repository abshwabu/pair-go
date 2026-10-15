import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../storage/token_storage.dart';

/// Types of realtime events streamed from the native WebSocket hub.
enum RealtimeEventType {
  message,
  typing,
  presence,
  reconnect,
  unknown,
}

/// Represents a parsed realtime event received over the WebSocket.
class RealtimeEvent {
  final RealtimeEventType type;
  final Map<String, dynamic> data;
  final String podId;
  final DateTime timestamp;

  const RealtimeEvent({
    required this.type,
    required this.data,
    required this.podId,
    required this.timestamp,
  });

  factory RealtimeEvent.fromJson({
    required Map<String, dynamic> json,
    required String podId,
  }) {
    final rawType = json['type'] as String? ?? '';
    RealtimeEventType eventType;
    switch (rawType) {
      case 'message':
        eventType = RealtimeEventType.message;
        break;
      case 'typing':
        eventType = RealtimeEventType.typing;
        break;
      case 'presence':
        eventType = RealtimeEventType.presence;
        break;
      default:
        eventType = RealtimeEventType.unknown;
    }

    final rawData = json['data'];
    final dataMap = rawData is Map<String, dynamic>
        ? rawData
        : (rawData is Map ? rawData.cast<String, dynamic>() : <String, dynamic>{});

    return RealtimeEvent(
      type: eventType,
      data: dataMap,
      podId: podId,
      timestamp: DateTime.now().toUtc(),
    );
  }

  factory RealtimeEvent.reconnect(String podId) {
    return RealtimeEvent(
      type: RealtimeEventType.reconnect,
      data: const {},
      podId: podId,
      timestamp: DateTime.now().toUtc(),
    );
  }

  @override
  String toString() => 'RealtimeEvent(type: $type, podId: $podId, data: $data)';
}

/// Status of the WebSocket connection.
enum RealtimeConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

typedef WebSocketChannelFactory = WebSocketChannel Function(
  Uri uri,
  Map<String, dynamic> headers,
);

/// Riverpod provider for [RealtimeClient].
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final client = RealtimeClient(tokenStorage: tokenStorage);
  ref.onDispose(() {
    client.dispose();
  });
  return client;
});

/// Client managing native WebSockets per pod with exponential backoff reconnects,
/// lifecycle resume handling, and stream broadcasting.
class RealtimeClient with WidgetsBindingObserver {
  final TokenStorage tokenStorage;
  final String baseUrl;
  final WebSocketChannelFactory? _channelFactory;

  String? _activePodId;
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  Timer? _reconnectTimer;
  Duration _reconnectDelay = const Duration(seconds: 1);
  bool _isExplicitlyClosed = false;
  bool _hasConnectedOnce = false;

  final _eventController = StreamController<RealtimeEvent>.broadcast();
  final _statusController = StreamController<RealtimeConnectionStatus>.broadcast();
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.disconnected;

  RealtimeClient({
    required this.tokenStorage,
    String? baseUrl,
    WebSocketChannelFactory? channelFactory,
  })  : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://localhost:8085/api/v1',
            ),
        _channelFactory = channelFactory {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Broadcast stream of incoming realtime events.
  Stream<RealtimeEvent> get events => _eventController.stream;

  /// Broadcast stream of connection status changes.
  Stream<RealtimeConnectionStatus> get status => _statusController.stream;

  RealtimeConnectionStatus get currentStatus => _status;
  String? get activePodId => _activePodId;

  /// Helper deriving ws:// or wss:// base URL from the configured HTTP base URL.
  static String deriveWebSocketUrl(String apiBaseUrl) {
    var trimmed = apiBaseUrl.trim();
    if (trimmed.startsWith('https://')) {
      trimmed = 'wss://${trimmed.substring(8)}';
    } else if (trimmed.startsWith('http://')) {
      trimmed = 'ws://${trimmed.substring(7)}';
    } else if (!trimmed.startsWith('ws://') && !trimmed.startsWith('wss://')) {
      trimmed = 'ws://$trimmed';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// Connects to the WebSocket hub for [podId].
  Future<void> connect(String podId) async {
    if (podId.isEmpty) return;

    if (_activePodId == podId &&
        (_status == RealtimeConnectionStatus.connected ||
            _status == RealtimeConnectionStatus.connecting)) {
      return;
    }

    // Close any previous pod session
    _cleanupSession();

    _activePodId = podId;
    _isExplicitlyClosed = false;
    _reconnectDelay = const Duration(seconds: 1);
    _hasConnectedOnce = false;

    await _establishConnection();
  }

  Future<void> _establishConnection() async {
    if (_isExplicitlyClosed || _activePodId == null) return;

    final podId = _activePodId!;
    _setStatus(
      _hasConnectedOnce
          ? RealtimeConnectionStatus.reconnecting
          : RealtimeConnectionStatus.connecting,
    );

    try {
      final token = await tokenStorage.getToken();
      final wsBase = deriveWebSocketUrl(baseUrl);

      final uri = Uri.parse('$wsBase/pods/$podId/ws').replace(
        queryParameters:
            token != null && token.isNotEmpty ? {'token': token} : null,
      );

      final headers = <String, dynamic>{
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final WebSocketChannel channel;
      if (_channelFactory != null) {
        channel = _channelFactory(uri, headers);
      } else {
        channel = IOWebSocketChannel.connect(
          uri,
          headers: headers,
          pingInterval: const Duration(seconds: 15),
        );
      }
      _channel = channel;

      final isReconnect = _hasConnectedOnce;
      _setStatus(RealtimeConnectionStatus.connected);
      _reconnectDelay = const Duration(seconds: 1);
      _hasConnectedOnce = true;

      if (isReconnect) {
        // Emit reconnect event so UI/providers can immediately refetch latest messages
        _eventController.add(RealtimeEvent.reconnect(podId));
      }

      _channelSubscription = channel.stream.listen(
        (data) => _handleIncomingData(data, podId),
        onError: (error) {
          _handleDisconnect();
        },
        onDone: () {
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleIncomingData(dynamic raw, String podId) {
    try {
      String text;
      if (raw is String) {
        text = raw;
      } else if (raw is List<int>) {
        text = utf8.decode(raw);
      } else {
        return;
      }

      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final event = RealtimeEvent.fromJson(json: decoded, podId: podId);
        _eventController.add(event);
      }
    } catch (_) {
      // Ignore malformed payloads
    }
  }

  void _handleDisconnect() {
    _cleanupChannelOnly();

    if (_isExplicitlyClosed || _activePodId == null) {
      _setStatus(RealtimeConnectionStatus.disconnected);
      return;
    }

    _setStatus(RealtimeConnectionStatus.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_isExplicitlyClosed || _activePodId == null) return;

    final delay = _reconnectDelay;
    // Exponential backoff capped at 30 seconds
    final nextSeconds = min(delay.inSeconds * 2, 30);
    _reconnectDelay = Duration(seconds: nextSeconds == 0 ? 1 : nextSeconds);

    _reconnectTimer = Timer(delay, () async {
      if (!_isExplicitlyClosed && _activePodId != null) {
        await _establishConnection();
      }
    });
  }

  /// Closes the active socket connection for the current pod.
  void disconnect() {
    _isExplicitlyClosed = true;
    _cleanupSession();
    _setStatus(RealtimeConnectionStatus.disconnected);
  }

  void _cleanupChannelOnly() {
    _channelSubscription?.cancel();
    _channelSubscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _cleanupSession() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupChannelOnly();
    _activePodId = null;
  }

  void _setStatus(RealtimeConnectionStatus next) {
    if (_status != next) {
      _status = next;
      _statusController.add(next);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isExplicitlyClosed &&
          _activePodId != null &&
          _status != RealtimeConnectionStatus.connected) {
        // App resumed: cancel pending backoff timer and reconnect immediately
        _reconnectTimer?.cancel();
        _reconnectDelay = const Duration(seconds: 1);
        _establishConnection();
      }
    }
  }

  /// Disposes streams, listeners, and observers.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disconnect();
    _eventController.close();
    _statusController.close();
  }
}
