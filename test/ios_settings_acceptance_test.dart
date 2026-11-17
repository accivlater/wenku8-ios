import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_palette.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/haptic_preferences.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/performance_preferences.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/setting_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
  });

  tearDown(() => state.dispose());

  Future<LibraryState> reload() async {
    final restored = await LibraryState.load();
    addTearDown(restored.dispose);
    return restored;
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  test('应用外观语言排版和玻璃设置经重载保留', () async {
    await state.setTheme(ThemeMode.dark);
    await state.setLanguage(AppLanguage.simplified);
    await state.setAppPalette(
      const AppPalettePreferences(
        source: AppPaletteSource.custom,
        seed: 0xff547d98,
      ),
    );
    await state.setTypography(fontSize: 22, lineHeight: 1.9);
    await state.setGlassBlur(13);
    await state.setGlassOpacity(.42);
    await state.setReduceMotion(true);
    await state.setForcePortrait(true);
    await state.setDirectReadingPages({
      ReadingEntry.shelf,
      ReadingEntry.local,
    });

    final restored = await reload();
    expect(restored.theme, ThemeMode.dark);
    expect(restored.language, AppLanguage.simplified);
    expect(restored.appPalette.source, AppPaletteSource.custom);
    expect(restored.appPalette.seed, 0xff547d98);
    expect(restored.fontSize, 22);
    expect(restored.lineHeight, 1.9);
    expect(restored.glassBlur, 13);
    expect(restored.glassOpacity, .42);
    expect(restored.reduceMotion, isTrue);
    expect(restored.forcePortrait, isTrue);
    expect(restored.directReading, isTrue);
    expect(restored.directReadingPages, {
      ReadingEntry.shelf,
      ReadingEntry.local,
    });
    expect(restored.directReadingOn(ReadingEntry.discovery), isFalse);
  });

  test('未提交的滑杆预览即时可见但不会写入重载状态', () async {
    await state.setTypography(fontSize: 20, lineHeight: 1.8);
    await state.setReaderPreferences(
      const ReaderPreferences(paper: ReaderPaper.milk),
    );
    await state.setGlassBlur(10);
    await state.setGlassOpacity(.5);

    await state.setTypography(
      fontSize: 26,
      lineHeight: 2.1,
      persist: false,
    );
    await state.setReaderPreferences(
      const ReaderPreferences(paper: ReaderPaper.night),
      persist: false,
    );
    await state.setGlassBlur(22, persist: false);
    await state.setGlassOpacity(.2, persist: false);
    expect(
      (state.fontSize, state.lineHeight, state.glassBlur, state.glassOpacity),
      (26.0, 2.1, 22.0, .2),
    );
    expect(state.readerPreferences.paper, ReaderPaper.night);

    final restored = await reload();
    expect(
      (
        restored.fontSize,
        restored.lineHeight,
        restored.glassBlur,
        restored.glassOpacity,
      ),
      (20.0, 1.8, 10.0, .5),
    );
    expect(restored.readerPreferences.paper, ReaderPaper.milk);
  });

  test('低性能和振动设置具有实际筛选作用并经重载保留', () async {
    const performance = PerformancePreferences(
      enabled: true,
      effects: {
        PerformanceEffect.motion,
        PerformanceEffect.animatedIcons,
      },
    );
    await state.setPerformance(performance);
    expect(state.performance.glass, isFalse);
    expect(state.performance.blur, isFalse);
    expect(state.performance.motion, isTrue);
    expect(state.performance.animatedIcons, isTrue);
    expect(state.effectiveReduceMotion, isFalse);
    await state.setPerformance(
      performance.withEffect(PerformanceEffect.motion, false),
    );
    expect(state.effectiveReduceMotion, isTrue);
    await state.setPerformance(performance);

    final haptics = const HapticPreferences()
        .withCategoryStrength(HapticCategory.controls, HapticStrength.light)
        .withCategoryStrength(HapticCategory.shelf, HapticStrength.strong)
        .withCategoryEnabled(HapticCategory.shelf, false);
    await state.setHaptics(haptics);
    expect(state.haptics.levelFor(HapticCategory.controls), HapticStrength.light);
    expect(state.haptics.levelFor(HapticCategory.shelf), isNull);

    final restored = await reload();
    expect(restored.performance, performance);
    expect(restored.haptics, haptics);
    await restored.setHaptics(restored.haptics.withEnabled(false));
    expect(
      HapticCategory.values.every(
        (category) => restored.haptics.levelFor(category) == null,
      ),
      isTrue,
    );

    final disabled = await reload();
    expect(disabled.haptics.enabled, isFalse);
    expect(
      disabled.haptics.forCategory(HapticCategory.shelf).strength,
      HapticStrength.strong,
    );
    expect(disabled.haptics.forCategory(HapticCategory.shelf).enabled, isFalse);
  });

  test('全部阅读偏好字段经序列化和重载保持一致', () async {
    const preferences = ReaderPreferences(
      paper: ReaderPaper.night,
      margin: 30,
      marginLeft: 11,
      marginRight: 22,
      marginTop: 13,
      marginBottom: 14,
      paragraphGap: 18,
      indent: true,
      justify: true,
      tapPaging: true,
      tapBothSidesNext: false,
      volumePaging: true,
      brightness: .64,
      autoScrollSpeed: 33,
      mode: ReaderMode.paged,
      tapLayout: ReaderTapLayout.rightHand,
      edgeBrightness: true,
      pageEffect: ReaderPageEffect.slide,
      pageSpeed: ReaderPageSpeed.quick,
      hideSystemStatus: true,
      reflowOnChrome: false,
      chapterEntrance: true,
      nightTextBrightness: .7,
      letterSpacing: 1.2,
      textWeight: ReaderTextWeight.medium,
      statusSideInset: 12,
      backgroundOpacity: .4,
      backgroundFit: BoxFit.contain,
    );
    await state.setReaderPreferences(preferences);

    final restored = await reload();
    expect(restored.readerPreferences.toJson(), preferences.toJson());
    expect(restored.readerPreferences.leftMargin, 11);
    expect(restored.readerPreferences.rightMargin, 22);
    expect(restored.readerPreferences.bindingMargin, 16.5);
  });

  test('逐书排版覆盖与通用设置分别持久化且可恢复通用', () async {
    await state.setReaderPreferences(
      const ReaderPreferences(paper: ReaderPaper.milk),
    );
    await state.setIndependentReaderStyle(7, true);
    await state.setTypography(fontSize: 24, lineHeight: 2.05, bookId: 7);
    await state.setReaderPreferences(
      state.readerPreferencesFor(7).copyWith(
        mode: ReaderMode.vertical,
        paper: ReaderPaper.night,
        indent: true,
      ),
      bookId: 7,
    );
    await state.setReaderTypeface('system', bookId: 7);
    await state.setHiddenReaderLanguages(7, {'ja'}, onlyLanguage: 'zh');

    final restored = await reload();
    expect(restored.independentReaderStyle(7), isTrue);
    expect(restored.readerFontSizeFor(7), 24);
    expect(restored.readerLineHeightFor(7), 2.05);
    expect(restored.readerTypefaceFor(7), 'system');
    expect(restored.readerPreferencesFor(7).mode, ReaderMode.vertical);
    expect(restored.readerPreferencesFor(7).paper, ReaderPaper.night);
    expect(restored.readerPreferencesFor(7).indent, isTrue);
    expect(restored.hiddenReaderLanguagesFor(7), {'ja'});
    expect(restored.onlyReaderLanguageFor(7), 'zh');
    expect(restored.readerPreferences.mode, ReaderMode.scroll);
    expect(restored.readerPreferences.paper, ReaderPaper.milk);
    expect(restored.fontSize, 19);

    await restored.setIndependentReaderStyle(7, false);
    final shared = await reload();
    expect(shared.independentReaderStyle(7), isFalse);
    expect(shared.readerPreferencesFor(7).mode, ReaderMode.scroll);
    expect(shared.readerPreferencesFor(7).paper, ReaderPaper.milk);
    expect(shared.readerFontSizeFor(7), 19);
  });

  testWidgets('外观菜单取消无副作用且确认选择后重载保留', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: state.settingsChanges,
            builder: (context, _) => GlassSettingMenu<ThemeMode>(
              icon: CupertinoIcons.moon_stars,
              label: '外观模式',
              value: state.theme,
              options: const {
                ThemeMode.system: '跟随系统',
                ThemeMode.light: '浅色',
                ThemeMode.dark: '深色',
              },
              reduceMotion: true,
              onChanged: state.setTheme,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menuContext = tester.element(find.byType(GlassSettingMenu<ThemeMode>));

    await tester.tap(find.text('外观模式'));
    await tester.pumpAndSettle();
    expect(find.text('深色'), findsOneWidget);
    Navigator.of(menuContext).pop();
    await tester.pumpAndSettle();
    expect(state.theme, ThemeMode.system);
    expect(preferences.containsKey('theme'), isFalse);

    await tester.tap(find.text('外观模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await flush(tester);
    expect(state.theme, ThemeMode.dark);
    final restored = (await tester.runAsync(LibraryState.load))!;
    addTearDown(restored.dispose);
    expect(restored.theme, ThemeMode.dark);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
