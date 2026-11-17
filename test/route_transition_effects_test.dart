import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/native_effects.dart';

Widget _glass(Widget child) => NativeGlassGroup(
  child: NativeBackdrop(
    effect: NativeEffect.glass,
    blur: 8,
    tint: const Color(0xddfffdf8),
    child: child,
  ),
);

Widget _routePage(Widget child) => child;

void _expectLite(WidgetTester tester, bool expected) {
  for (final lens in tester.widgetList<LiquidGlassLens>(
    find.byType(LiquidGlassLens),
  )) {
    expect(lens.style.liteGlass, expected);
    if (expected) expect(lens.style.blur, 0);
  }
}

void main() {
  testWidgets('source and destination reduce effects only during a route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => RouteTransitionEffects(
            animation: ModalRoute.of(context)?.animation,
            secondaryAnimation: ModalRoute.of(context)?.secondaryAnimation,
            child: Column(
              children: [
                Expanded(child: _glass(const Text('来源页'))),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    softRoute<void>(_routePage(_glass(const Text('详情页')))),
                  ),
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectLite(tester, false);

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(LiquidGlassLens), findsNWidgets(2));
    _expectLite(tester, RouteTransitionEffects.lightweight);
    await tester.pumpAndSettle();
    _expectLite(tester, false);

    Navigator.of(tester.element(find.text('详情页'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    _expectLite(tester, RouteTransitionEffects.lightweight);
    await tester.pumpAndSettle();
    _expectLite(tester, false);
    expect(find.text('来源页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('effect changes preserve the editable subtree', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 420),
    );
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => RouteTransitionEffects(
              animation: controller,
              secondaryAnimation: null,
              child: _glass(TextField(focusNode: focus)),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.enterText(find.byType(TextField), '转场不清空');
    final before = tester.state<EditableTextState>(find.byType(EditableText));
    final forward = controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    _expectLite(tester, RouteTransitionEffects.lightweight);
    await tester.pumpAndSettle();
    _expectLite(tester, false);
    expect(
      identical(
        tester.state<EditableTextState>(find.byType(EditableText)),
        before,
      ),
      isTrue,
    );
    expect(find.text('转场不清空'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await forward;
  });

  testWidgets('iOS cover flight matches the Cupertino route duration', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final route = softRoute<void>(const SizedBox.shrink(), paperFlight: true);
    expect(
      route.transitionDuration,
      CupertinoRouteTransitionMixin.kTransitionDuration,
    );
    expect(
      route.reverseTransitionDuration,
      CupertinoRouteTransitionMixin.kTransitionDuration,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
