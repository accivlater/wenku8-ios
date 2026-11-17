import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/network_status.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MockStreamHandlerEventSink sink;
  late List<MethodCall> currentCalls;
  String? current;

  setUp(() {
    currentCalls = [];
    current = 'online';
    messenger.setMockMethodCallHandler(NetworkStatus.methods, (call) async {
      currentCalls.add(call);
      return current;
    });
    messenger.setMockStreamHandler(
      NetworkStatus.events,
      MockStreamHandler.inline(
        onListen: (_, events) => sink = events,
        onCancel: (_) {},
      ),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(NetworkStatus.methods, null);
    messenger.setMockStreamHandler(NetworkStatus.events, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform 启动时订阅路径事件并读取当前状态', () async {
      debugDefaultTargetPlatformOverride = platform;
      final status = NetworkStatus();
      addTearDown(status.dispose);

      await status.start();

      expect(currentCalls.map((call) => call.method), ['current']);
      expect(status.value, NetworkReachability.online);
      await status.start();
      expect(currentCalls, hasLength(1));
    });
  }

  test('iOS 网络事件去抖去重，恢复在线会取消离线延迟', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final status = NetworkStatus();
    addTearDown(status.dispose);
    await status.start();
    var notifications = 0;
    status.addListener(() => notifications++);

    sink.success('offline');
    sink.success('offline');
    await _flush();
    expect(status.value, NetworkReachability.online);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(status.value, NetworkReachability.offline);
    expect(notifications, 1);

    sink.success('offline');
    await _flush();
    sink.success('online');
    await _flush();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(status.value, NetworkReachability.online);
    expect(notifications, 2);
  });

  test('初始离线与未知状态不被延迟逻辑误改', () async {
    final status = NetworkStatus();
    addTearDown(status.dispose);
    status.accept('offline', initial: true);
    expect(status.value, NetworkReachability.offline);
    status.accept('checking');
    status.accept('online');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(status.value, NetworkReachability.online);
    status.accept(null);
    expect(status.value, NetworkReachability.unknown);
  });

  test('非移动平台不请求原生网络通道', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final status = NetworkStatus(initial: NetworkReachability.offline);
    addTearDown(status.dispose);
    await status.start();
    expect(currentCalls, isEmpty);
    expect(status.value, NetworkReachability.offline);
  });
}
