import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_palette.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/haptic_preferences.dart';
import 'package:wenku8_flutter/haptic_settings_page.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/local_platform.dart';
import 'package:wenku8_flutter/low_performance_page.dart';
import 'package:wenku8_flutter/palette_settings_page.dart';
import 'package:wenku8_flutter/performance_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    AppHaptics.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppHaptics.channel, (call) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalPlatform.channel, (call) async {
          return call.method == 'flushPreferences' ? true : null;
        });
  });

  tearDown(() {
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
    AppHaptics.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppHaptics.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocalPlatform.channel, null);
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(theme: novelTheme(Brightness.light), home: page),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('iOS 主题配色逐项操作、取消非法输入并重载', (tester) async {
    await show(tester, PaletteSettingsPage(state: state));
    await tap(
      tester,
      find.byKey(const ValueKey('palette-source-custom')),
    );
    const colors = <int, String>{
      0xff607d71: '雾松',
      0xff547d98: '浅海',
      0xff887aa5: '鸢尾',
      0xffa06a77: '胭脂',
      0xff9b8452: '麦穗',
      0xff72767d: '石墨',
    };
    for (final entry in colors.entries) {
      await tap(
        tester,
        find.descendant(
          of: find.byKey(ValueKey('palette-swatch-${entry.key}')),
          matching: find.text(entry.value),
        ),
      );
      expect(state.appPalette.seed, entry.key, reason: entry.value);
    }
    await tap(tester, find.byKey(const ValueKey('palette-custom-color')));
    await tester.enterText(find.byKey(const ValueKey('palette-hex')), '非法');
    await tester.pump();
    expect(
      tester
          .widget<GlassTextButton>(
            find.byKey(const ValueKey('palette-apply-color')),
          )
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(state.appPalette.seed, colors.keys.last);

    await tap(tester, find.byKey(const ValueKey('palette-custom-color')));
    for (var index = 0; index < 3; index++) {
      final slider = tester.widget<AppGlassSlider>(
        find.byType(AppGlassSlider).at(index),
      );
      slider.onChanged!(index == 0 ? .4 : index == 1 ? .6 : .8);
      await tester.pump();
    }
    final editedHex = tester
        .widget<CupertinoTextField>(
          find.byKey(const ValueKey('palette-hex')),
        )
        .controller!
        .text;
    expect(parsePaletteHex(editedHex), isNotNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(state.appPalette.seed, colors.keys.last);

    await tap(tester, find.byKey(const ValueKey('palette-custom-color')));
    await tester.enterText(
      find.byKey(const ValueKey('palette-hex')),
      '123ABC',
    );
    await tester.pump();
    await tap(tester, find.byKey(const ValueKey('palette-apply-color')));
    expect(state.appPalette.seed, 0xff123abc);
    final restored = await LibraryState.load();
    addTearDown(restored.dispose);
    debugDefaultTargetPlatformOverride = null;
    expect(restored.appPalette.source, AppPaletteSource.custom);
    expect(restored.appPalette.seed, 0xff123abc);
  });

  testWidgets('iOS 低性能六个独立开关与恢复预设均实际操作', (tester) async {
    await show(tester, LowPerformancePage(state: state));
    await tap(tester, find.byKey(const ValueKey('low-performance-mode')));
    expect(state.performance.enabled, isTrue);
    for (final effect in PerformanceEffect.values) {
      expect(state.performance.allows(effect), isFalse);
      await tap(tester, find.byKey(ValueKey(effect.preferenceKey)));
      expect(state.performance.allows(effect), isTrue, reason: effect.label);
      expect(state.performance.effects, contains(effect));
      expect(
        state.performance.effects.length,
        PerformanceEffect.values.indexOf(effect) + 1,
      );
    }
    await tap(tester, find.byKey(const ValueKey('performance-light-preset')));
    expect(state.performance.enabled, isTrue);
    expect(state.performance.effects, isEmpty);
    await tester.drag(
      find.byKey(const ValueKey('performance-options-scroll')),
      const Offset(0, 1200),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppGlassSwitch>(
            find.byKey(const ValueKey('low-performance-mode')),
          )
          .onChanged,
      isNotNull,
    );
    await tap(tester, find.byKey(const ValueKey('low-performance-mode')));
    expect(state.performance.enabled, isFalse);
    final restored = await LibraryState.load();
    addTearDown(restored.dispose);
    debugDefaultTargetPlatformOverride = null;
    expect(restored.performance, state.performance);
  });

  testWidgets('iOS 振动总开关、七分类、强度与系统结果语义', (tester) async {
    await show(tester, HapticSettingsPage(state: state));
    await tap(tester, find.byKey(const ValueKey('haptic-global-enabled')));
    expect(state.haptics.enabled, isFalse);
    for (final category in HapticCategory.values) {
      expect(state.haptics.levelFor(category), isNull);
      expect(state.haptics.forCategory(category).enabled, isTrue);
    }
    await tap(tester, find.byKey(const ValueKey('haptic-global-enabled')));
    final all = find.byKey(const ValueKey('haptic-all-strength'));
    await tap(
      tester,
      find.descendant(of: all, matching: find.text('强')),
    );
    expect(state.haptics.uniformStrength, HapticStrength.strong);
    for (final category in HapticCategory.values) {
      final enabled = find.byKey(
        ValueKey('haptic-${category.name}-enabled'),
      );
      await tap(tester, enabled);
      expect(state.haptics.forCategory(category).enabled, isFalse);
      expect(state.haptics.levelFor(category), isNull);
      expect(state.haptics.forCategory(category).strength, HapticStrength.strong);
      await tap(tester, enabled);
      if (category == HapticCategory.result) {
        expect(find.text('强度由系统控制'), findsOneWidget);
        continue;
      }
      final strength = find.byKey(
        ValueKey('haptic-${category.name}-strength'),
      );
      await tap(
        tester,
        find.descendant(of: strength, matching: find.text('轻')),
      );
      expect(state.haptics.forCategory(category).strength, HapticStrength.light);
      await tap(tester, find.byKey(ValueKey('haptic-${category.name}-preview')));
    }
    expect(state.haptics.uniformStrength, isNull);
    expect(find.text('已分别设置'), findsOneWidget);
    final restored = await LibraryState.load();
    addTearDown(restored.dispose);
    debugDefaultTargetPlatformOverride = null;
    expect(restored.haptics, state.haptics);
  });
}
