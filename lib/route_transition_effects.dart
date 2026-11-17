import 'package:flutter/widgets.dart';

class RouteTransitionEffects extends StatefulWidget {
  const RouteTransitionEffects({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  static const lightweight = bool.fromEnvironment(
    'LIGHTWEIGHT_ROUTE_EFFECTS',
    defaultValue: true,
  );

  final Animation<double>? animation;
  final Animation<double>? secondaryAnimation;
  final Widget child;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_RouteTransitionEffectsScope>()
          ?.active ??
      false;

  @override
  State<RouteTransitionEffects> createState() => _RouteTransitionEffectsState();
}

class _RouteTransitionEffectsState extends State<RouteTransitionEffects> {
  bool _active = false;

  static bool _moving(Animation<double>? animation) {
    final status = animation?.status;
    return status == AnimationStatus.forward ||
        status == AnimationStatus.reverse;
  }

  void _update() {
    final active =
        RouteTransitionEffects.lightweight &&
        (_moving(widget.animation) || _moving(widget.secondaryAnimation));
    if (active == _active) return;
    setState(() => _active = active);
  }

  void _listen() {
    widget.animation?.addStatusListener(_statusChanged);
    widget.secondaryAnimation?.addStatusListener(_statusChanged);
    _update();
  }

  void _unlisten(Animation<double>? animation) {
    animation?.removeStatusListener(_statusChanged);
  }

  void _statusChanged(AnimationStatus status) => _update();

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(RouteTransitionEffects oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _unlisten(oldWidget.animation);
      _unlisten(oldWidget.secondaryAnimation);
      _listen();
    }
  }

  @override
  Widget build(BuildContext context) =>
      _RouteTransitionEffectsScope(active: _active, child: widget.child);

  @override
  void dispose() {
    _unlisten(widget.animation);
    _unlisten(widget.secondaryAnimation);
    super.dispose();
  }
}

class _RouteTransitionEffectsScope extends InheritedWidget {
  const _RouteTransitionEffectsScope({
    required this.active,
    required super.child,
  });

  final bool active;

  @override
  bool updateShouldNotify(_RouteTransitionEffectsScope oldWidget) =>
      active != oldWidget.active;
}
