import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';

class _RecordingSearchRepository extends DemoNovelRepository {
  final queries = <String>[];
  final pending = <String, Completer<List<Novel>>>{};

  @override
  Future<List<Novel>> search(String query) {
    queries.add(query);
    return (pending[query] ??= Completer<List<Novel>>()).future;
  }

  void complete(String query, List<Novel> books) {
    pending[query]!.complete(books);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryState state;
  late GlobalKey<HomeShellState> homeKey;
  late _RecordingSearchRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'reduceMotion': true});
    state = await LibraryState.load();
    homeKey = GlobalKey<HomeShellState>();
    repository = _RecordingSearchRepository();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: HomeShell(key: homeKey, state: state, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    final pending = homeKey.currentState!.searchBooks(query);
    await tester.pump();
    await pending;
  }

  TextField searchField(WidgetTester tester) => tester.widget<TextField>(
    find.byKey(const ValueKey('expanded-search-input')),
  );

  testWidgets('searchBooks 呈现关键词并进入真实结果和最近搜索', (tester) async {
    await mount(tester);

    await search(tester, '星尘');

    expect(searchField(tester).controller!.text, '星尘');
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
    expect(repository.queries, ['星尘']);

    repository.complete('星尘', [demoNovels.first]);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();

    expect(find.text('找到 1 个结果'), findsOneWidget);
    expect(state.recentSearches, ['星尘']);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('searchBooks 空白关键词只沿用打开搜索和聚焦流程', (tester) async {
    await mount(tester);

    await search(tester, '  \t  ');
    await tester.pump(const Duration(milliseconds: 300));

    expect(searchField(tester).controller!.text, isEmpty);
    expect(searchField(tester).focusNode!.hasFocus, isTrue);
    expect(repository.queries, ['']);
    expect(state.recentSearches, isEmpty);

    repository.complete('', const []);
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关故事'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('searchBooks 不重复发起默认、防抖或相同关键词请求', (tester) async {
    await mount(tester);

    await search(tester, '重复关键词');
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.queries, ['重复关键词']);

    await search(tester, '重复关键词');
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.queries, ['重复关键词']);
    expect(searchField(tester).controller!.text, '重复关键词');

    repository.complete('重复关键词', [demoNovels.first]);
    await tester.pumpAndSettle();
    expect(find.text('找到 1 个结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
