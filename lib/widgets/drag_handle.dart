import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:window_manager/window_manager.dart';

const double _handleSize = kDotSize;
const Duration _hideDelay = Duration(milliseconds: 20);
const Duration _hideDuration = Duration(milliseconds: 200);

// Spring physics
const double _springStiffness = 300.0;
const double _springDamping = 15.0;
const double _offsetScale = 0.15;
const double _maxSpringOffset = 5.0;
const double _springEpsilon = 0.01;

class DragHandle extends StatefulWidget {
  final bool dragging;
  final bool showWindowContent;

  const DragHandle({
    super.key,
    required this.dragging,
    required this.showWindowContent,
  });

  @override
  State<DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<DragHandle>
    with TickerProviderStateMixin, WindowListener {
  bool _hovering = false;
  Timer? _hideTimer;
  late final AnimationController _showController;
  late final Animation<double> _curved;

  // Spring physics state
  Offset _springOffset = Offset.zero;
  Offset _springVelocity = Offset.zero;
  Offset? _lastWindowPos;
  bool _posQueryInFlight = false;
  late final Ticker _springTicker;
  Duration? _lastTickTime;

  bool get _shouldBeVisible => widget.dragging || widget.showWindowContent;

  @override
  void initState() {
    super.initState();
    _showController = AnimationController(
      vsync: this,
      duration: kHoverDuration,
      reverseDuration: _hideDuration,
      value: _shouldBeVisible ? 1.0 : 0.0,
    );
    _curved = CurvedAnimation(
      parent: _showController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _springTicker = createTicker(_onSpringTick);
    windowManager.addListener(this);
  }

  @override
  void didUpdateWidget(DragHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldBeVisible) {
      _hideTimer?.cancel();
      _hideTimer = null;
      _showController.forward();
    } else if (_hideTimer == null && _showController.value > 0) {
      _hideTimer = Timer(_hideDelay, () {
        _showController.reverse();
        _hideTimer = null;
      });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _hideTimer?.cancel();
    _springTicker.dispose();
    _showController.dispose();
    super.dispose();
  }

  // -- Spring physics --

  @override
  void onWindowMove() {
    if (_posQueryInFlight) return;
    _posQueryInFlight = true;
    windowManager.getPosition().then((pos) {
      if (!mounted) return;
      _posQueryInFlight = false;
      final last = _lastWindowPos;
      _lastWindowPos = pos;
      if (last != null) {
        final delta = pos - last;
        _springOffset -= delta * _offsetScale;
        if (_springOffset.distance > _maxSpringOffset) {
          _springOffset =
              _springOffset / _springOffset.distance * _maxSpringOffset;
        }
        _ensureTickerRunning();
      }
    });
  }

  @override
  void onWindowMoved() {
    _lastWindowPos = null;
  }

  void _ensureTickerRunning() {
    if (_springTicker.isActive) return;
    _lastTickTime = null;
    _springTicker.start();
  }

  void _onSpringTick(Duration elapsed) {
    final dt = switch (_lastTickTime) {
      final last? => (elapsed - last).inMicroseconds / 1e6,
      null => 0.016,
    }
        .clamp(0.001, 0.033);
    _lastTickTime = elapsed;

    // Semi-implicit Euler integration
    final accel =
        _springOffset * -_springStiffness + _springVelocity * -_springDamping;
    _springVelocity = _springVelocity + accel * dt;
    _springOffset = _springOffset + _springVelocity * dt;

    if (_springOffset.distance < _springEpsilon &&
        _springVelocity.distance < _springEpsilon) {
      _springTicker.stop();
      _springOffset = Offset.zero;
      _springVelocity = Offset.zero;
      _lastTickTime = null;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHandleActive = _hovering || widget.dragging;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: ScaleTransition(
        scale: _curved,
        child: GestureDetector(
          onPanStart: (details) => windowManager.startDragging(),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: AnimatedScale(
              scale: isHandleActive ? 1.1 : 1.0,
              duration: kHoverDuration,
              curve: kHoverCurve,
              child: AnimatedContainer(
                duration: kHoverDuration,
                curve: kHoverCurve,
                width: _handleSize,
                height: _handleSize,
                decoration: BoxDecoration(
                  color:
                      isHandleActive ? colors.border : colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(kRadiusMd),
                  border: Border.all(color: colors.textOnPrimary, width: 2),
                ),
                child: Center(
                  child: Transform.translate(
                    offset: _springOffset,
                    child: AnimatedContainer(
                      duration: kHoverDuration,
                      curve: kHoverCurve,
                      width: isHandleActive ? 10.0 : 5.0,
                      height: isHandleActive ? 10.0 : 5.0,
                      decoration: BoxDecoration(
                        color:
                            isHandleActive
                                ? Colors.transparent
                                : colors.textOnPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.textOnPrimary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
