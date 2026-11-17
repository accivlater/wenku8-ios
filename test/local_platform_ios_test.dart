import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/local_platform.dart';
import 'package:wenku8_flutter/reader_preferences.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late LibraryState state;
  late Object owner;
  late List<MethodCall> toolCalls;
  late List<MethodCall> readerCalls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
    owner = Object();
    toolCalls = [];
    readerCalls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(LocalPlatform.channel, (call) async {
      toolCalls.add(call);
      if (call.method == 'getKeepScreenOn') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(LocalPlatform.readerControls, (
      call,
    ) async {
      readerCalls.add(call);
      return null;
    });
  });

  tearDown(() async {
    LocalPlatform.keepScreen(owner, false);
    LocalPlatform.reader(owner, active: false, state: state);
    await _flush();
    LocalPlatform.readerControls.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(LocalPlatform.channel, null);
    messenger.setMockMethodCallHandler(LocalPlatform.readerControls, null);
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS 亮屏按所有者计数并可读取系统状态', () async {
    expect(LocalPlatform.ios, isTrue);
    expect(LocalPlatform.readerSupported, isTrue);
    expect(await LocalPlatform.getKeepScreenOn(), isTrue);

    LocalPlatform.keepScreen(owner, true);
    LocalPlatform.keepScreen(owner, true);
    await _flush();
    expect(toolCalls.where((call) => call.method == 'keepScreenOn'), hasLength(1));
    expect(toolCalls.last.arguments, isTrue);

    final other = Object();
    LocalPlatform.keepScreen(other, true);
    LocalPlatform.keepScreen(owner, false);
    await _flush();
    expect(toolCalls.where((call) => call.method == 'keepScreenOn'), hasLength(1));
    LocalPlatform.keepScreen(other, false);
    await _flush();
    expect(toolCalls.last.method, 'keepScreenOn');
    expect(toolCalls.last.arguments, isFalse);
  });

  test('iOS 阅读亮度使用原生通道并禁用 Android 专属控制', () async {
    await state.setReaderPreferences(
      const ReaderPreferences(
        brightness: .42,
        volumePaging: true,
        hideSystemStatus: true,
      ),
    );

    LocalPlatform.reader(owner, active: true, state: state);
    await _flush();
    expect(readerCalls.single.method, 'apply');
    expect(readerCalls.single.arguments, {
      'active': true,
      'volumePaging': false,
      'brightness': .42,
      'hideStatusBar': false,
    });

    LocalPlatform.reader(owner, active: false, state: state);
    await _flush();
    expect(readerCalls.last.arguments, {
      'active': false,
      'volumePaging': false,
      'brightness': null,
      'hideStatusBar': false,
    });
  });
}
