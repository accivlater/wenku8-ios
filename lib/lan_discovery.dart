import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LanNearbyDevice {
  const LanNearbyDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });
  final String id, name, host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is LanNearbyDevice &&
      other.id == id &&
      other.name == name &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(id, name, host, port);
}

/// The platform owns mDNS reception. No subnet/port scans or cloud directory.
class LanDiscovery {
  LanDiscovery({TargetPlatform? platform}) : _platform = platform;

  static const serviceType = '_wenkuread._tcp';
  static const _channel = MethodChannel('org.mewx.wenku8/lan_discovery');
  static const _events = EventChannel('org.mewx.wenku8/lan_discovery_events');
  final TargetPlatform? _platform;
  final _changes = StreamController<List<LanNearbyDevice>>.broadcast();
  final _devices = <String, LanNearbyDevice>{};
  StreamSubscription<dynamic>? _eventSubscription;
  String? _ownId;
  int _generation = 0;
  bool _disposed = false, _listening = false;

  Stream<List<LanNearbyDevice>> get changes => _changes.stream;
  String name = '我的设备';
  bool available = false;
  String? error;
  bool get _ios => (_platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  bool _current(int generation) =>
      !_disposed && generation == _generation && !_changes.isClosed;

  void _publish() {
    if (!_changes.isClosed) {
      _changes.add(List<LanNearbyDevice>.unmodifiable(_devices.values));
    }
  }

  String _describeFailure(Object failure) {
    if (failure is MissingPluginException) {
      return '当前系统暂不支持自动发现，请使用手动连接';
    }
    if (failure is PlatformException) {
      final code = failure.code.toLowerCase();
      if (code.contains('permission') ||
          code.contains('denied') ||
          code.contains('restricted')) {
        return '未获得本地网络权限，请在系统设置中允许后重新发现，或使用手动连接';
      }
      if (code.contains('offline') ||
          code.contains('network') ||
          code.contains('unavailable')) {
        return '当前局域网不可用，请连接同一 Wi-Fi 或手机热点后重试';
      }
      if (failure.message?.trim().isNotEmpty == true) {
        return failure.message!;
      }
    }
    return '自动发现暂不可用，请检查 Wi-Fi 与本地网络权限，或使用手动连接';
  }

  Future<void> _ignoreMethod(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // 原生停止操作幂等；自动发现不可用时仍可手动配对。
    }
  }

  Future<void> _stopIos() async {
    _listening = false;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    final pending = <Future<void>>[
      _ignoreMethod('stopDiscovery'),
      _ignoreMethod('stopAdvertising'),
      if (subscription != null)
        () async {
          try {
            await subscription.cancel();
          } catch (_) {
            // 事件流可能已由原生侧结束。
          }
        }(),
    ];
    await Future.wait(pending);
  }

  void _fail(Object failure, int generation) {
    if (!_current(generation)) return;
    _generation++;
    available = false;
    error = _describeFailure(failure);
    _devices.clear();
    _publish();
    if (_ios) unawaited(_stopIos());
  }

  void _onIosEvent(Object? raw, int generation) {
    if (!_current(generation) || raw is! Map) return;
    final type = raw['type'];
    if (type == 'error') {
      final message = raw['message'] ?? raw['error'];
      _fail(
        PlatformException(
          code: '${raw['code'] ?? 'LAN_DISCOVERY'}',
          message: message is String ? message : null,
        ),
        generation,
      );
      return;
    }
    if (type != 'found' && type != 'lost') return;
    final label = raw['name'], advertisedId = raw['id'];
    if (label is! String || label.isEmpty || label.length > 64) return;
    final id = advertisedId is String && advertisedId.isNotEmpty
        ? advertisedId
        : label;
    if (id.length > 64) return;
    if (type == 'lost') {
      if (_devices.remove(id) != null) _publish();
      return;
    }
    final host = raw['host'], port = raw['port'];
    if (id == _ownId ||
        host is! String ||
        host.isEmpty ||
        port is! int ||
        port < 1024 ||
        port > 65535) {
      return;
    }
    final device = LanNearbyDevice(id: id, name: label, host: host, port: port);
    if (_devices[id] == device ||
        !_devices.containsKey(id) && _devices.length >= 64) {
      return;
    }
    _devices[id] = device;
    _publish();
  }

  void _listenIos(int generation) {
    _listening = true;
    _eventSubscription = _events.receiveBroadcastStream().listen(
      (event) => _onIosEvent(event, generation),
      onError: (Object failure) => _fail(failure, generation),
      onDone: () {
        if (_listening && _current(generation)) {
          _fail(
            PlatformException(
              code: 'LAN_DISCOVERY_CLOSED',
              message: '设备发现已中断，请重新发现',
            ),
            generation,
          );
        }
      },
    );
  }

  Future<void> _startIos(String id, int port, int generation) async {
    await _stopIos();
    if (!_current(generation)) return;
    _listenIos(generation);
    final arguments = {
      'id': id,
      'name': name,
      'port': port,
      'service': serviceType,
    };
    try {
      await _channel.invokeMethod<dynamic>('startDiscovery', arguments);
      if (!_current(generation)) return;
      final advertised = await _channel.invokeMethod<dynamic>(
        'startAdvertising',
        arguments,
      );
      if (!_current(generation)) return;
      if (advertised is String && advertised.isNotEmpty && advertised != id) {
        name = advertised;
      }
      available = true;
    } catch (failure) {
      if (!_current(generation)) return;
      await _stopIos();
      if (!_current(generation)) return;
      available = false;
      error = _describeFailure(failure);
      _devices.clear();
      _publish();
    }
  }

  Future<void> _startAndroid(String id, int port, int generation) async {
    _channel.setMethodCallHandler((call) async {
      if (!_current(generation)) return;
      if (call.method == 'failure') {
        _fail(PlatformException(code: 'LAN_DISCOVERY'), generation);
        return;
      }
      if (call.method != 'devices' || call.arguments is! List) return;
      final devices = <LanNearbyDevice>[];
      for (final value in call.arguments as List) {
        if (value is! Map ||
            value['id'] is! String ||
            value['name'] is! String ||
            value['host'] is! String ||
            value['port'] is! int) {
          continue;
        }
        devices.add(
          LanNearbyDevice(
            id: value['id'],
            name: value['name'],
            host: value['host'],
            port: value['port'],
          ),
        );
      }
      if (!_changes.isClosed) _changes.add(devices);
    });
    try {
      name =
          await _channel.invokeMethod<String>('start', {
            'id': id,
            'port': port,
          }) ??
          name;
      if (!_current(generation)) return;
      available = true;
    } catch (failure) {
      if (!_current(generation)) return;
      available = false;
      error = _describeFailure(failure);
    }
  }

  Future<void> start(String id, int port) async {
    if (_disposed) return;
    final generation = ++_generation;
    _ownId = id;
    available = false;
    error = null;
    _devices.clear();
    if (_ios) {
      await _startIos(id, port, generation);
    } else {
      await _startAndroid(id, port, generation);
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _generation++;
    available = false;
    error = null;
    _ownId = null;
    _devices.clear();
    _publish();
    if (_ios) {
      await _stopIos();
    } else {
      await _ignoreMethod('stop');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _listening = false;
    _channel.setMethodCallHandler(null);
    if (_ios) {
      unawaited(_stopIos());
    } else {
      unawaited(_ignoreMethod('stop'));
    }
    _devices.clear();
    unawaited(_changes.close());
  }
}
