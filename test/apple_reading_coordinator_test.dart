import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/apple_capabilities.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/listening/controller.dart';
import 'package:wenku8_flutter/listening/models.dart';
import 'package:wenku8_flutter/listening/store.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/pages.dart';

import 'support/listening_fixture.dart';

class _LoggingDemoRepository extends DemoNovelRepository {
  final findCalls = <int>[];
  final searchCalls = <String>[];

  @override
  Future<Novel?> find(int id) {
    findCalls.add(id);
    return super.find(id);
  }

  @override
  Future<List<Novel>> search(String query) {
    searchCalls.add(query);
    return super.search(query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  final nativePending = <Object?>[];
  final nativeIndexIds = <int>{};
  late LibraryState state;
  late _LoggingDemoRepository repository;
  late FakeListeningOutput output;
  late FakeSpeechAudio audio;
  ListeningController? listening;

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

  Future<void> settle(WidgetTester tester) async {
    for (var index = 0; index < 8; index++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<String?> dispatch(
    WidgetTester tester,
    Map<String, Object?> action,
  ) async {
    final response = emitAction(action);
    await settle(tester);
    return response;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
    await state.setReduceMotion(true);
    repository = _LoggingDemoRepository();
    output = FakeListeningOutput();
    audio = FakeSpeechAudio();
    listening = null;
    calls.clear();
    nativePending.clear();
    nativeIndexIds.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(AppleCapabilities.channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'activate':
          final pending = List<Object?>.of(nativePending);
          nativePending.clear();
          return pending;
        case 'indexedBookIDs':
          return nativeIndexIds.toList();
        case 'indexBooks':
          final arguments = call.arguments as Map<Object?, Object?>;
          for (final book in arguments['books'] as List<Object?>) {
            nativeIndexIds.add((book as Map)['bookId'] as int);
          }
        case 'removeIndexes':
          final arguments = call.arguments as Map<Object?, Object?>;
          nativeIndexIds.removeAll(
            (arguments['bookIds'] as List<Object?>).cast<int>(),
          );
        case 'removeAllIndexes':
          nativeIndexIds.clear();
      }
      return null;
    });
  });

  tearDown(() async {
    if (listening != null) await listening!.dispose();
    if (!output.positionEvents.isClosed) await output.dispose();
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(AppleCapabilities.channel, null);
  });

  Future<void> mount(WidgetTester tester, {bool withListening = false}) async {
    if (withListening) {
      listening = ListeningController(
        repository: repository,
        audio: audio,
        store: ListeningStore(await SharedPreferences.getInstance()),
        outputFactory: (_) async => output,
      );
    }
    await tester.pumpWidget(
      NovelApp(state: state, repository: repository, listening: listening),
    );
    await settle(tester);
    expect(calls.any((call) => call.method == 'activate'), isTrue);
    expect(calls.any((call) => call.method == 'donateActions'), isTrue);
  }

  Future<void> unmount(WidgetTester tester) async {
    final controller = listening;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    if (controller != null) {
      final closing = controller.dispose();
      for (var index = 0; index < 8; index++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await closing;
      listening = null;
    }
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> savePosition(
    WidgetTester tester,
    Novel book,
    int chapter,
    double offset, {
    int paragraph = 4,
    int textOffset = 42,
  }) => tester.runAsync(
    () => state.savePosition(
      novel: book,
      chapter: chapter,
      offset: offset,
      maximum: 1000,
      width: 640,
      paragraphIndex: paragraph,
      paragraphFraction: 0.3,
      textOffset: textOffset,
      textScale: 1.2,
      typeface: 'system',
      contentRevision: 'revision-fixture',
    ),
  );

  testWidgets('冷启动 Spotlight 打开真实章节和 offset，热动作去重', (tester) async {
    final book = demoNovels.first;
    await savePosition(tester, book, 1, 40);
    final existing = state.positionFor(book.id)!;
    nativePending.add({
      'id': 'cold-open-book',
      'action': 'openBook',
      'bookId': book.id,
      'position': {
        'chapter': 1,
        'chapterId': 0,
        'offset': 120.0,
        'fraction': 0.12,
        'paragraphIndex': 4,
        'paragraphFraction': 0.3,
        'textOffset': 42,
        'updatedAt': existing.updatedAt + 1000,
      },
    });

    await mount(tester);

    expect(find.byType(ReaderPage), findsOneWidget);
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(reader.novel.id, book.id);
    expect(reader.initialChapter, 1);
    final restored = reader.initialPosition!;
    expect(restored.chapter, 1);
    expect(restored.offset, 120);
    expect(restored.fraction, 0.12);
    expect(restored.fontSize, existing.fontSize);
    expect(restored.width, 640);
    expect(restored.lineHeight, existing.lineHeight);
    expect(restored.paragraphIndex, 4);
    expect(restored.paragraphFraction, 0.3);
    expect(restored.textOffset, 42);
    expect(restored.textScale, 1.2);
    expect(restored.typeface, 'system');
    expect(restored.layout, existing.layout);
    expect(restored.contentRevision, 'revision-fixture');
    expect(repository.findCalls.where((id) => id == book.id), hasLength(1));

    expect(
      await dispatch(tester, {
        'id': 'cold-open-book',
        'action': 'openBook',
        'bookId': book.id,
      }),
      'handled',
    );
    expect(repository.findCalls.where((id) => id == book.id), hasLength(1));
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
    expect(calls.where((call) => call.method == 'deactivate'), hasLength(1));
  });

  testWidgets('最新在读书缺失时取消续读，不回退打开第一本', (tester) async {
    await savePosition(tester, demoNovels.first, 0, 20);
    final missing = Novel(
      id: 999,
      title: '已缺失书籍',
      author: '作者',
      genre: '',
      summary: '',
      colors: const [Colors.black],
      chapters: const [NovelChapter('第一章', '正文')],
    );
    await savePosition(tester, missing, 0, 30);
    nativePending.add({'id': 'cold-continue', 'action': 'continueReading'});

    await mount(tester);
    await tester.pump();

    expect(find.byType(ReaderPage), findsNothing);
    expect(repository.findCalls, contains(999));
    expect(repository.findCalls, isNot(contains(demoNovels.first.id)));
    expect(find.text('这本书已不在本机，未打开其他书籍'), findsOneWidget);
    expect(
      await dispatch(tester, {'id': 'no-history', 'action': 'startListening'}),
      'cancelled',
    );
    expect(find.text('当前版本没有可用的听书播放器'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('快捷搜索显示真实结果且相同动作不重复请求', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('dock-tab-1')));
    await tester.pumpAndSettle();
    const action = {
      'id': 'search-moonlight',
      'action': 'searchBooks',
      'query': '月光',
    };

    expect(await dispatch(tester, action), 'handled');

    final input = find.byKey(const ValueKey('expanded-search-input'));
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '月光');
    expect(find.text('找到 1 个结果'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InlineSearchResults),
        matching: find.text('月光航线'),
      ),
      findsWidgets,
    );
    expect(
      repository.searchCalls.where((query) => query == '月光'),
      hasLength(1),
    );

    expect(await dispatch(tester, action), 'handled');
    expect(
      repository.searchCalls.where((query) => query == '月光'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('听书动作驱动真实控制器，暂停后恢复且换书先停旧会话', (tester) async {
    await savePosition(tester, demoNovels.first, 1, 80);
    await mount(tester, withListening: true);
    const start = {'id': 'listen-start', 'action': 'startListening'};

    expect(await dispatch(tester, start), 'handled');
    expect(listening!.snapshot.value.novel?.id, demoNovels.first.id);
    expect(listening!.snapshot.value.chapter, 1);
    expect(listening!.snapshot.value.phase, ListeningPhase.playing);
    expect(listening!.snapshot.value.playRequested, isTrue);
    expect(output.playing, isTrue);
    expect(output.plays, 1);
    expect(output.loaded, hasLength(1));

    expect(await dispatch(tester, start), 'handled');
    expect(output.plays, 1);
    expect(
      await dispatch(tester, {
        'id': 'listen-pause',
        'action': 'pauseListening',
      }),
      'handled',
    );
    expect(listening!.snapshot.value.phase, ListeningPhase.paused);
    expect(output.playing, isFalse);

    expect(
      await dispatch(tester, {
        'id': 'listen-resume',
        'action': 'startListening',
      }),
      'handled',
    );
    expect(listening!.snapshot.value.phase, ListeningPhase.playing);
    expect(output.loaded, hasLength(1));
    expect(output.plays, 2);

    expect(
      await dispatch(tester, {
        'id': 'listen-other-book',
        'action': 'startListening',
        'bookId': demoNovels[1].id,
      }),
      'handled',
    );
    expect(listening!.snapshot.value.novel?.id, demoNovels[1].id);
    expect(listening!.snapshot.value.phase, ListeningPhase.playing);
    expect(output.stops, greaterThanOrEqualTo(1));
    expect(output.loaded, hasLength(2));
    expect(output.playing, isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('阅读记录批量去抖索引并删除失效本地 Spotlight 项', (tester) async {
    const deletedLocalId = 0x60000009;
    nativeIndexIds.addAll({1, 2, deletedLocalId});
    await savePosition(tester, demoNovels.first, 1, 40);
    await savePosition(tester, demoNovels[1], 0, 20);
    await mount(tester);

    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(nativeIndexIds, {1, 2});
    final removals = calls.where((call) => call.method == 'removeIndexes');
    expect(removals, hasLength(1));
    expect(removals.single.arguments, {'bookIds': contains(deletedLocalId)});
    final batches = calls.where((call) => call.method == 'indexBooks').toList();
    expect(batches, hasLength(1));
    final books = (batches.single.arguments as Map)['books'] as List;
    expect(books.map((book) => book['bookId']).toSet(), {1, 2});
    for (final book in books.cast<Map>()) {
      expect(book['title'], isNotEmpty);
      expect(book['author'], isNotEmpty);
      expect(book['chapterTitle'], isNotEmpty);
      expect(book['position'], isA<Map>());
      expect(book.containsKey('summary'), isFalse);
      expect(book.containsKey('content'), isFalse);
      expect(book.containsKey('cookie'), isFalse);
      expect(book['keywords'], isEmpty);
    }

    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(calls.where((call) => call.method == 'indexBooks'), hasLength(1));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
