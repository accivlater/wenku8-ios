import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/main.dart';
import 'package:wenku8_flutter/native_effects.dart';
import 'package:wenku8_flutter/performance_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real route transition frame workload', (tester) async {
    const lightPreset = bool.fromEnvironment('LIGHT_PRESET');
    const keepMotion = bool.fromEnvironment('KEEP_MOTION');
    const useStored = bool.fromEnvironment('USE_STORED_PERFORMANCE');
    const enableLightPreset = bool.fromEnvironment('ENABLE_LIGHT_PRESET');
    if (!useStored) {
      SharedPreferences.setMockInitialValues({
        'readerChromeVisible': true,
        'readerChromeHintSeen': true,
        'lowPerformanceMode': lightPreset,
        'performanceMotion': keepMotion,
        'performanceAnimatedIcons': keepMotion,
        'performanceShelf3d': keepMotion,
      });
    }
    final state = await LibraryState.load();
    addTearDown(state.dispose);
    if (enableLightPreset) {
      await state.setPerformance(const PerformancePreferences(enabled: true));
    }
    expect(state.performance.enabled, enableLightPreset || lightPreset);
    if (enableLightPreset || lightPreset) {
      expect(state.performance.effects, keepMotion ? isNotEmpty : isEmpty);
    }
    await NativeEffects.prepare();
    await tester.pumpWidget(
      NovelApp(state: state, repository: const DemoNovelRepository()),
    );
    await tester.pumpAndSettle();
    final samples = <Map<String, Object>>[];
    final directory = await getTemporaryDirectory();
    const optimized = bool.fromEnvironment(
      'LIGHTWEIGHT_ROUTE_EFFECTS',
      defaultValue: true,
    );
    final variant = useStored
        ? 'stored-light-preset'
        : lightPreset && keepMotion
        ? 'light-motion'
        : lightPreset
        ? 'light-preset'
        : optimized
        ? 'optimized'
        : 'baseline';
    final file = File('${directory.path}/route-transition-$variant.json');
    if (await file.exists()) await file.delete();
    Future<void> save() async {
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'variant': variant,
          'platform': defaultTargetPlatform.name,
          'completed': samples.length == 12,
          'samples': samples,
        }),
      );
    }

    await save();
    addTearDown(save);

    Map<String, Object> stats(List<FrameTiming> frames) {
      List<int> values(Duration Function(FrameTiming) select) =>
          frames.map((frame) => select(frame).inMicroseconds).toList()..sort();
      Map<String, Object> summary(List<int> sorted) => {
        'medianUs': sorted[sorted.length ~/ 2],
        'p95Us': sorted[((sorted.length - 1) * .95).round()],
        'maxUs': sorted.last,
        'over8333': sorted.where((value) => value > 8333).length,
        'over16667': sorted.where((value) => value > 16667).length,
      };
      return {
        'frames': frames.length,
        'build': summary(values((frame) => frame.buildDuration)),
        'raster': summary(values((frame) => frame.rasterDuration)),
        'span': summary(values((frame) => frame.totalSpan)),
      };
    }

    Future<void> phase(String name, Future<void> Function() action) async {
      await tester.pumpAndSettle();
      final frames = <FrameTiming>[];
      void collect(List<FrameTiming> timings) => frames.addAll(timings);
      WidgetsBinding.instance.addTimingsCallback(collect);
      final clock = Stopwatch()..start();
      await action();
      final wallMs = clock.elapsedMilliseconds;
      final route = ModalRoute.of(tester.element(find.byType(Scaffold).last));
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      WidgetsBinding.instance.removeTimingsCallback(collect);
      expect(frames, isNotEmpty, reason: '$name 没有收到 FrameTiming');
      samples.add({
        'name': name,
        'wallMs': wallMs,
        'routeMs': route!.transitionDuration.inMilliseconds,
        'reverseMs': route.reverseTransitionDuration.inMilliseconds,
        ...stats(frames),
      });
      await save();
    }

    Future<void> tap(Finder finder) async {
      await tester.tap(finder);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    Finder back() => find
        .byWidgetPredicate(
          (widget) => widget is GlassIconButton && widget.label == '返回',
        )
        .last;

    await tap(find.byKey(const ValueKey('dock-tab-3')));
    await tap(find.byKey(const ValueKey('my-settings')));
    for (var index = 0; index < 3; index++) {
      await phase('settings-enter-$index', () => tap(find.text('使用方式')));
      await phase('settings-return-$index', () => tap(back()));
    }
    await tap(back());
    await tap(find.byKey(const ValueKey('dock-tab-0')));
    await tap(
      find.byWidgetPredicate(
        (widget) => widget is GlassIconButton && widget.label == '搜索',
      ),
    );
    expect(find.text(demoNovels.first.title), findsWidgets);
    for (var index = 0; index < 3; index++) {
      await phase(
        'detail-enter-$index',
        () => tap(find.text(demoNovels.first.title).last),
      );
      await phase('detail-return-$index', () => tap(back()));
    }

    await save();
    debugPrint('ROUTE_TRANSITION_METRICS=${file.path}');
    expect(samples, hasLength(12));
  });
}
