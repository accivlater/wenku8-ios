import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/lan_discovery.dart';

const _channel = MethodChannel('org.mewx.wenku8/lan_discovery');
const _events = EventChannel('org.mewx.wenku8/lan_discovery_events');
const _own = '00000000000000000000000000000000';
const _peer = '11111111111111111111111111111111';
const _other = '22222222222222222222222222222222';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late MockStreamHandlerEventSink sink;
  late int cancels;
  String? failStart;
  Object? startResult;

  setUp(() {
    calls = [];
    cancels = 0;
    failStart = null;
    startResult = null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == failStart) {
        throw PlatformException(code: 'LOCAL_NETWORK_PERMISSION_DENIED');
      }
      if (call.method == 'start') return startResult;
      if (call.method == 'startAdvertising') return startResult;
      return null;
    });
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (_, events) => sink = events,
        onCancel: (_) => cancels++,
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockStreamHandler(_events, null);
  });

  LanDiscovery create(TargetPlatform platform) {
    final discovery = LanDiscovery(platform: platform);
    addTearDown(() async {
      await discovery.stop();
      discovery.dispose();
    });
    return discovery;
  }

  test('iOS 默认 DNS-SD 服务与 Android 现有协议一致', () {
    expect(LanDiscovery.serviceType, '_wenkuread._tcp');
  });

  test('iOS 使用约定通道启动发现与广播，并处理重复、更新和丢失事件', () async {
    final discovery = create(TargetPlatform.iOS);
    final batches = <List<LanNearbyDevice>>[];
    final subscription = discovery.changes.listen(batches.add);
    addTearDown(subscription.cancel);

    await discovery.start(_own, 38762);
    expect(discovery.available, isTrue);
    expect(discovery.error, isNull);
    for (final method in ['startDiscovery', 'startAdvertising']) {
      final call = calls.singleWhere((call) => call.method == method);
      expect(call.arguments, {
        'id': _own,
        'name': '我的设备',
        'port': 38762,
        'service': '_wenkuread._tcp',
      });
    }

    Map<String, Object> found(String id, String host, [int port = 38762]) => {
      'type': 'found',
      'id': id,
      'name': '设备 ${id.substring(0, 2)}',
      'host': host,
      'port': port,
    };

    sink.success(found(_peer, '192.168.1.20'));
    await _flush();
    expect(batches, hasLength(1));
    expect(batches.single.single.id, _peer);
    expect(batches.single.single.name, '设备 11');
    expect(batches.single.single.host, '192.168.1.20');

    sink.success(found(_peer, '192.168.1.20'));
    sink.success(found(_own, '192.168.1.10'));
    sink.success({'type': 'found', 'name': _other, 'host': '', 'port': 38762});
    await _flush();
    expect(batches, hasLength(1), reason: '重复、自身和无效事件不应刷新设备列表');

    sink.success(found(_peer, '192.168.1.21', 39000));
    await _flush();
    expect(batches, hasLength(2));
    expect(batches.last.single.host, '192.168.1.21');
    expect(batches.last.single.port, 39000);

    sink.success(found(_other, 'fe80::1234'));
    await _flush();
    expect(batches.last.map((device) => device.id), {_peer, _other});
    sink.success({'type': 'lost', 'name': _peer});
    await _flush();
    expect(batches.last.map((device) => device.id), [_other]);

    await discovery.stop();
    expect(discovery.available, isFalse);
    expect(batches.last, isEmpty);
    expect(calls.map((call) => call.method), contains('stopDiscovery'));
    expect(calls.map((call) => call.method), contains('stopAdvertising'));
    expect(cancels, greaterThan(0));
  });

  test('iOS 权限拒绝不伪报可用，取消后可重新启动', () async {
    final discovery = create(TargetPlatform.iOS);
    failStart = 'startAdvertising';
    await discovery.start(_own, 38762);
    expect(discovery.available, isFalse);
    expect(discovery.error, contains('本地网络权限'));
    expect(calls.map((call) => call.method), contains('stopDiscovery'));

    failStart = null;
    startResult = '测试 iPhone';
    await discovery.start(_own, 38762);
    expect(discovery.available, isTrue);
    expect(discovery.error, isNull);
    expect(discovery.name, '测试 iPhone');
    await discovery.stop();
    expect(discovery.error, isNull);
  });

  test('iOS 原生错误和离线事件清除设备并保留可读的失败状态', () async {
    final discovery = create(TargetPlatform.iOS);
    final batches = <List<LanNearbyDevice>>[];
    final subscription = discovery.changes.listen(batches.add);
    addTearDown(subscription.cancel);
    await discovery.start(_own, 38762);
    sink.success({
      'type': 'found',
      'name': _peer,
      'host': '192.168.1.20',
      'port': 38762,
    });
    await _flush();
    expect(batches.last, hasLength(1));

    sink.success({'type': 'error', 'code': 'LOCAL_NETWORK_PERMISSION_DENIED'});
    await _flush();
    expect(discovery.available, isFalse);
    expect(discovery.error, contains('本地网络权限'));
    expect(batches.last, isEmpty);

    await discovery.start(_own, 38762);
    sink.error(code: 'NETWORK_UNAVAILABLE');
    await _flush();
    expect(discovery.available, isFalse);
    expect(discovery.error, contains('局域网不可用'));
  });

  test('Android 保留旧 start/stop 与 devices 回调协议', () async {
    startResult = '测试 Android';
    final discovery = create(TargetPlatform.android);
    final batches = <List<LanNearbyDevice>>[];
    final subscription = discovery.changes.listen(batches.add);
    addTearDown(subscription.cancel);
    await discovery.start(_own, 38762);
    expect(discovery.available, isTrue);
    expect(discovery.name, '测试 Android');
    expect(calls.map((call) => call.method), isNot(contains('startDiscovery')));
    final start = calls.singleWhere((call) => call.method == 'start');
    expect(start.arguments, {'id': _own, 'port': 38762});

    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      _channel.name,
      codec.encodeMethodCall(
        const MethodCall('devices', [
          {'id': _peer, 'name': '旧设备', 'host': '192.168.1.30', 'port': 38762},
        ]),
      ),
      null,
    );
    await _flush();
    expect(batches.last.single.name, '旧设备');
    await discovery.stop();
    expect(calls.map((call) => call.method), contains('stop'));
    expect(discovery.available, isFalse);
  });
}
