import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/backup_page.dart';
import 'package:wenku8_flutter/home_navigation.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/listening/models.dart';
import 'package:wenku8_flutter/listening/store.dart';
import 'package:wenku8_flutter/local_import_options.dart';
import 'package:wenku8_flutter/local_import_settings_page.dart';
import 'package:wenku8_flutter/local_library_preferences.dart';
import 'package:wenku8_flutter/network_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<LibraryState> reload() async {
    final restored = await LibraryState.load();
    addTearDown(restored.dispose);
    return restored;
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
  }

  test('使用方式开关真实改变首页标签并在重载后保持', () async {
    final network = NetworkStatus(initial: NetworkReachability.offline);
    addTearDown(network.dispose);
    final navigation = HomeNavigation(state, network);
    addTearDown(navigation.dispose);
    expect(navigation.tabs, [1, 2, 3]);

    await state.setNavigationMode(adaptWhenOffline: false);
    expect(navigation.tabs, [0, 1, 2, 3]);
    await state.setNavigationMode(combinedShelf: true);
    expect(navigation.tabs, [0, 1, 3]);
    await state.setNavigationMode(adaptWhenOffline: true);
    expect(navigation.tabs, [1, 3]);
    await state.setNavigationMode(localReaderMode: true);
    expect(navigation.tabs, [1, 3]);
    await state.setNavigationMode(combinedShelf: false);
    expect(navigation.tabs, [2, 3]);
    expect(navigation.destination(0), 2);

    final restored = await reload();
    final restoredNavigation = HomeNavigation(restored, network);
    addTearDown(restoredNavigation.dispose);
    expect(restoredNavigation.tabs, [2, 3]);
    expect(restoredNavigation.localReader, isTrue);
    expect(restoredNavigation.combinedShelf, isFalse);
  });

  test('书架视图搜索历史和本地分类设置经重载保留', () async {
    await state.setShelfView(
      sort: 'title',
      filter: 'reading',
      layout: 'list',
      source: 'cached',
    );
    await state.recordSearch('  荷莉的手记  ');
    await state.recordSearch('Alpha');
    await state.recordSearch('alpha');
    await state.recordSearch('   ');
    await state.recordSearch('bad\u0000query');

    final organization = state.organization;
    final group = await organization.addGroup('科幻');
    await organization.assign(101, group);
    await organization.select(group, shelf: true);
    await organization.setView(LocalLibraryView.list);
    await organization.setSort(LocalLibrarySort.title);
    await organization.setReadingFilter('reading');

    final restored = await reload();
    expect(restored.shelfSort, 'title');
    expect(restored.shelfFilter, 'reading');
    expect(restored.shelfLayout, 'list');
    expect(restored.shelfSourceFilter, 'cached');
    expect(restored.recentSearches, ['alpha', '荷莉的手记']);

    final preferences = await SharedPreferences.getInstance();
    final restoredOrganization = LocalLibraryPreferences(preferences)..load();
    addTearDown(restoredOrganization.dispose);
    expect(restoredOrganization.view, LocalLibraryView.list);
    expect(restoredOrganization.sort, LocalLibrarySort.title);
    expect(restoredOrganization.readingFilter, 'reading');
    expect(restoredOrganization.shelfSelected, group);
    expect(restoredOrganization.groupOf(101), group);
    expect(restoredOrganization.nameOf(group), '科幻');
  });

  test('重载字符串数组不依赖 List<String> 精确运行时类型', () async {
    SharedPreferences.setMockInitialValues({
      'shelf': <Object>['71'],
      'reading_history_hidden': <Object>['72'],
      'local_shelf_hidden': <Object>['1610612736'],
      'recentSearches': <Object>['  荷莉的手记  '],
    });
    final restored = await reload();
    expect(restored.shelf, {71});
    expect(restored.hiddenLocalBooks, {0x60000000});
    expect(restored.recentSearches, ['荷莉的手记']);
  });

  test('听书音色语速跟随分语言和续听游标经重载保留', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = ListeningStore(preferences);
    const englishVoice = SpeechVoice(
      id: 'en-US-AriaNeural',
      label: 'English test voice',
      source: ListeningSource.edge,
      locale: 'en-US',
    );
    const cursor = ListeningCursor(
      novelId: 7,
      chapterId: 70,
      chapter: 2,
      paragraph: 4,
      start: 12,
      positionMs: 3456,
      segmentHash: 'test-segment',
    );
    await store.saveVoice(alternateEdgeVoice);
    await store.saveSpeed(1.75);
    await store.saveFollow(false);
    await store.saveSpokenLanguage(7, 'zh-CN');
    await store.saveLanguageVoice(alternateEdgeVoice, 'en-US', englishVoice);
    await store.saveCursor(cursor);

    final restored = ListeningStore(preferences);
    expect(restored.voice.id, alternateEdgeVoice.id);
    expect(restored.speed, 1.75);
    expect(restored.follow, isFalse);
    expect(restored.spokenLanguage(7), 'zh');
    expect(
      restored.languageVoices(alternateEdgeVoice)['en']?.id,
      englishVoice.id,
    );
    expect(restored.cursor(7)?.toJson(), cursor.toJson());

    await restored.saveSpeed(99);
    expect(restored.speed, listeningMaximumSpeed);
    expect(ListeningStore(preferences).speed, listeningMaximumSpeed);
  });

  test('Apple 系统音色把既有和新增语速限制在原生支持范围', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = ListeningStore(preferences);
    await store.saveSpeed(3);
    const voice = SpeechVoice(
      id: 'com.apple.voice.compact.zh-CN.Tingting',
      label: '婷婷',
      source: ListeningSource.system,
      engine: '@default',
    );
    await store.saveVoice(voice);
    expect(store.speed, listeningSystemMaximumSpeed);
    expect(ListeningStore(preferences).speed, listeningSystemMaximumSpeed);
    await store.saveSpeed(99);
    expect(store.speed, listeningSystemMaximumSpeed);
    expect(preferences.getDouble('listening.speed.v1'), 2);
  });

  test('导入目录拒绝无效规则且有效规则经重载保留', () async {
    final preferences = await SharedPreferences.getInstance();
    const invalid = LocalImportOptions(customToc: true, chapterRule: '[');
    await expectLater(
      state.organization.setImportOptions(invalid),
      throwsFormatException,
    );
    expect(preferences.getString(LocalImportOptions.preferenceKey), isNull);
    expect(state.organization.importOptions.isDefault, isTrue);

    const valid = LocalImportOptions(
      customToc: true,
      chapterRule: r'^【.+】$',
      volumeRule: r'^卷\s+\d+',
      autoTitles: false,
    );
    await state.organization.setImportOptions(valid);
    final restored = LocalLibraryPreferences(preferences);
    addTearDown(restored.dispose);
    expect(restored.importOptions.toJson(), valid.toJson());
  });

  testWidgets('导入目录编辑后返回取消不会保存草稿', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: LocalImportSettingsPage(library: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义规则'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('import-chapter-rule')),
      r'^【.+】$',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('import-options-save')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('返回'));
    await tester.pumpAndSettle();
    expect(preferences.getString(LocalImportOptions.preferenceKey), isNull);
    expect(state.organization.importOptions.isDefault, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('备份恢复预览取消后书架外观和存储均不变', (tester) async {
    final encoded = await tester.runAsync(() async {
      await state.setTheme(ThemeMode.light);
      await state.setShelfMembership(7, true);
      final backup = await state.createBackup();
      final text = await backup.encode();
      await state.setShelfMembership(7, false);
      await state.setShelfMembership(42, true);
      await state.setTheme(ThemeMode.dark);
      return text;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': encoded};
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: LibraryBackupPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('backup-paste')),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pump();
    expect(find.text('正在读取备份…'), findsOneWidget);
    await flush(tester);
    final backupError = find.byKey(const ValueKey('backup-error'));
    expect(
      backupError,
      findsNothing,
      reason: backupError.evaluate().isEmpty
          ? null
          : tester
                .widget<Text>(
                  find.descendant(of: backupError, matching: find.byType(Text)),
                )
                .data,
    );
    expect(find.byKey(const ValueKey('backup-preview')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('backup-preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-preview')), findsOneWidget);
    expect(state.shelf, {42});
    expect(state.theme, ThemeMode.dark);

    await tester.ensureVisible(find.text('取消恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消恢复'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-preview')), findsNothing);
    expect(state.shelf, {42});
    expect(state.shelf.contains(7), isFalse);
    expect(state.theme, ThemeMode.dark);

    final restored = (await tester.runAsync(LibraryState.load))!;
    addTearDown(restored.dispose);
    expect(restored.shelf, {42});
    expect(restored.shelf.contains(7), isFalse);
    expect(restored.theme, ThemeMode.dark);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
