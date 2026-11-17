import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/apple_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  final nativePending = <Object?>[];
  Completer<List<Object?>>? activationGate;
  late AppleCapabilities capabilities;

  Future<String?> emitAction(Map<String, Object?> action) async {
    String? result;
    await messenger.handlePlatformMessage(
      AppleCapabilities.channel.name,
      codec.encodeMethodCall(MethodCall('performAction', action)),
      (ByteData? data) {
        if (data != null) result = codec.decodeEnvelope(data) as String?;
      },
    );
    return result;
  }

  setUp(() {
    calls.clear();
    nativePending.clear();
    activationGate = null;
    capabilities = AppleCapabilities();
    messenger.setMockMethodCallHandler(AppleCapabilities.channel, (call) async {
      calls.add(call);
      if (call.method == 'activate') {
        if (activationGate case final gate?) return gate.future;
        final pending = List<Object?>.of(nativePending);
        nativePending.clear();
        return pending;
      }
      return null;
    });
  });

  tearDown(() async {
    await capabilities.dispose();
    messenger.setMockMethodCallHandler(AppleCapabilities.channel, null);
  });

  test('书籍索引保留章节和阅读坐标，并可更新与移除', () async {
    const bookId = 0x60000001;
    const book = AppleBookIndex(
      bookId: bookId,
      title: '本地书籍',
      author: '作者甲',
      chapterTitle: '第一章',
      position: AppleReadingPosition(
        chapter: 0,
        chapterId: 101,
        offset: 24,
        fraction: 0.1,
        paragraphIndex: 2,
        textOffset: 12,
        updatedAt: 100,
      ),
      keywords: ['奇幻', '本地'],
    );

    await capabilities.indexBook(book);
    await capabilities.updateReadingProgress(
      book,
      const AppleReadingPosition(
        chapter: 3,
        chapterId: 204,
        offset: 96.5,
        fraction: 0.625,
        paragraphIndex: 8,
        paragraphFraction: 0.5,
        textOffset: 73,
        updatedAt: 200,
      ),
      chapterTitle: '第四章',
    );
    await capabilities.removeIndex(bookId);
    await capabilities.removeIndexes(const [7, 9]);
    await capabilities.removeAllIndexes();
    await capabilities.indexBooks(const []);
    await capabilities.removeIndexes(const []);

    expect(calls.map((call) => call.method), [
      'indexBooks',
      'indexBooks',
      'removeIndexes',
      'removeIndexes',
      'removeAllIndexes',
    ]);
    final first = calls[0].arguments as Map<Object?, Object?>;
    final indexed =
        (first['books'] as List<Object?>).single as Map<Object?, Object?>;
    expect(indexed, {
      'bookId': bookId,
      'title': '本地书籍',
      'author': '作者甲',
      'chapterTitle': '第一章',
      'position': {
        'chapter': 0,
        'chapterId': 101,
        'offset': 24.0,
        'fraction': 0.1,
        'paragraphIndex': 2,
        'paragraphFraction': 0.0,
        'textOffset': 12,
        'updatedAt': 100,
      },
      'keywords': ['奇幻', '本地'],
    });
    expect(indexed.keys, isNot(contains('account')));
    expect(indexed.keys, isNot(contains('cookie')));
    final updated =
        (calls[1].arguments as Map<Object?, Object?>)['books'] as List<Object?>;
    expect((updated.single as Map<Object?, Object?>)['position'], {
      'chapter': 3,
      'chapterId': 204,
      'offset': 96.5,
      'fraction': 0.625,
      'paragraphIndex': 8,
      'paragraphFraction': 0.5,
      'textOffset': 73,
      'updatedAt': 200,
    });
    expect((updated.single as Map<Object?, Object?>)['chapterTitle'], '第四章');
    expect(calls[2].arguments, {
      'bookIds': [bookId],
    });
    expect(calls[3].arguments, {
      'bookIds': [7, 9],
    });
  });

  test('冷启动缓存动作按序交付，Spotlight 位置完整且重复项去重', () async {
    nativePending.addAll([
      {
        'id': 'spotlight-book-1',
        'action': 'openBook',
        'bookId': 0x60000002,
        'position': {
          'chapter': 4,
          'chapterId': 405,
          'offset': 320.0,
          'fraction': 0.75,
          'paragraphIndex': 11,
          'paragraphFraction': 0.25,
          'textOffset': 55,
          'updatedAt': 300,
        },
      },
      {'id': 'spotlight-book-1', 'action': 'openBook', 'bookId': 0x60000002},
      {'id': 'cold-continue', 'action': 'continueReading'},
    ]);
    final actions = <AppleCapabilityAction>[];

    await capabilities.start((action) {
      actions.add(action);
      return AppleCapabilityActionResult.handled;
    });

    expect(capabilities.isActive, isTrue);
    expect(actions.map((action) => action.type), [
      AppleCapabilityActionType.openBook,
      AppleCapabilityActionType.continueReading,
    ]);
    expect(
      actions
          .singleWhere(
            (action) => action.type == AppleCapabilityActionType.openBook,
          )
          .bookId,
      0x60000002,
    );
    final position = actions.first.position!;
    expect(position.chapter, 4);
    expect(position.chapterId, 405);
    expect(position.offset, 320);
    expect(position.fraction, 0.75);
    expect(position.paragraphIndex, 11);
    expect(position.paragraphFraction, 0.25);
    expect(position.textOffset, 55);
    expect(position.updatedAt, 300);
    expect(nativePending, isEmpty);
  });

  test('继续阅读的后续动作只执行一次', () async {
    final actions = <AppleCapabilityAction>[];
    await capabilities.start((action) {
      actions.add(action);
      return AppleCapabilityActionResult.handled;
    });
    const action = {'id': 'continue-warm', 'action': 'continueReading'};

    expect(await emitAction(action), 'handled');
    expect(await emitAction(action), 'handled');

    expect(actions, hasLength(1));
    expect(actions.single.type, AppleCapabilityActionType.continueReading);
  });

  test('搜索书籍保留快捷指令关键词', () async {
    AppleCapabilityAction? received;
    await capabilities.start((action) {
      received = action;
      return AppleCapabilityActionResult.handled;
    });

    expect(
      await emitAction({
        'id': 'search-1',
        'action': 'searchBooks',
        'query': '无职转生 作者',
      }),
      'handled',
    );
    expect(received?.type, AppleCapabilityActionType.searchBooks);
    expect(received?.query, '无职转生 作者');
  });

  test('开始与暂停听书作为两个真实动作交付', () async {
    final actions = <AppleCapabilityAction>[];
    await capabilities.start((action) async {
      await Future<void>.delayed(Duration.zero);
      actions.add(action);
      return AppleCapabilityActionResult.handled;
    });

    expect(
      await emitAction({'id': 'listen-start', 'action': 'startListening'}),
      'handled',
    );
    expect(
      await emitAction({'id': 'listen-pause', 'action': 'pauseListening'}),
      'handled',
    );
    expect(actions.map((action) => action.type), [
      AppleCapabilityActionType.startListening,
      AppleCapabilityActionType.pauseListening,
    ]);
  });

  test('取消动作不会阻塞后续动作，并允许显式重试', () async {
    var accepted = false;
    final attempts = <String>[];
    await capabilities.start((action) {
      attempts.add(action.id);
      return accepted
          ? AppleCapabilityActionResult.handled
          : AppleCapabilityActionResult.cancelled;
    });
    const action = {'id': 'retryable', 'action': 'continueReading'};

    expect(await emitAction(action), 'cancelled');
    expect(await emitAction(action), 'cancelled');
    accepted = true;
    expect(await emitAction(action), 'handled');
    expect(attempts, ['retryable', 'retryable', 'retryable']);
  });

  test('动作回调异常按取消返回，并可用同一动作重试', () async {
    var fail = true;
    await capabilities.start((_) {
      if (fail) throw StateError('路由尚未就绪');
      return AppleCapabilityActionResult.handled;
    });
    const action = {'id': 'failed-route', 'action': 'openBook', 'bookId': 7};

    expect(await emitAction(action), 'cancelled');
    fail = false;
    expect(await emitAction(action), 'handled');
  });

  test('释放监听会停用通道，尚未完成的冷启动激活也会被取消', () async {
    activationGate = Completer<List<Object?>>();
    final actions = <AppleCapabilityAction>[];
    final starting = capabilities.start((action) {
      actions.add(action);
      return AppleCapabilityActionResult.handled;
    });
    await Future<void>.delayed(Duration.zero);
    final disposed = capabilities.dispose();
    activationGate!.complete([
      {'id': 'stale-cold-action', 'action': 'continueReading'},
    ]);

    await starting;
    await disposed;

    expect(actions, isEmpty);
    expect(capabilities.isActive, isFalse);
    expect(calls.map((call) => call.method), ['activate', 'deactivate']);
    expect(
      await emitAction({'id': 'after-dispose', 'action': 'pauseListening'}),
      isNull,
    );
  });

  test('原生已索引 ID 用于增量同步并忽略非法值', () async {
    messenger.setMockMethodCallHandler(AppleCapabilities.channel, (call) async {
      if (call.method == 'indexedBookIDs') return [1, 7.0, 'invalid'];
      return null;
    });

    expect(await capabilities.indexedBookIds(), {1, 7});
  });

  test('iOS 15 快捷动作捐赠只包含能力名称与显示短语', () async {
    await capabilities.prepareShortcuts();

    expect(calls.single.method, 'donateActions');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    final actions = arguments['actions'] as List<Object?>;
    expect(actions.map((action) => (action as Map)['action']), [
      'continueReading',
      'searchBooks',
      'startListening',
      'pauseListening',
    ]);
    for (final action in actions.cast<Map>()) {
      expect(action.keys.toSet(), {'action', 'title', 'phrase'});
    }
  });
}
