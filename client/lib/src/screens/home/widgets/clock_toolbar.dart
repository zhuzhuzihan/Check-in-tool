import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../models/attendance.dart';
import '../../../widgets/expressive_indicators.dart';

class ClockToolbar extends StatefulWidget {
  const ClockToolbar({
    super.key,
    required this.state,
    required this.isSubmitting,
    required this.biometricAvailable,
    required this.onClock,
  });

  final AttendanceState state;
  final bool isSubmitting;
  final bool biometricAvailable;
  final Future<void> Function(TouchMetrics metrics, ScreenMetrics screenMetrics)
  onClock;

  @override
  State<ClockToolbar> createState() => _ClockToolbarState();
}

class _ClockToolbarState extends State<ClockToolbar> {
  Duration? _pressedAt;
  Offset? _lastPosition;
  double _distance = 0;
  int _sampleCount = 0;
  TouchMetrics? _pendingMetrics;

  void _onPointerDown(PointerDownEvent event) {
    if (widget.isSubmitting) return;
    _pressedAt = event.timeStamp;
    _lastPosition = event.position;
    _distance = 0;
    _sampleCount = 1;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _lastPosition;
    if (_pressedAt == null || previous == null) return;
    _distance += (event.position - previous).distance;
    _lastPosition = event.position;
    _sampleCount++;
  }

  void _onPointerUp(PointerUpEvent event) {
    final started = _pressedAt;
    if (started == null) return;
    _pendingMetrics = TouchMetrics(
      duration: event.timeStamp - started,
      distance: _distance,
      sampleCount: math.max(1, _sampleCount),
    );
    _resetPointer();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pendingMetrics = null;
    _resetPointer();
  }

  void _resetPointer() {
    _pressedAt = null;
    _lastPosition = null;
    _distance = 0;
    _sampleCount = 0;
  }

  Future<void> _submit() async {
    if (widget.isSubmitting) return;
    final media = MediaQuery.of(context);
    final metrics = _pendingMetrics ?? const TouchMetrics.accessibility();
    _pendingMetrics = null;
    await widget.onClock(metrics, (
      width: media.size.width,
      height: media.size.height,
      pixelRatio: media.devicePixelRatio,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final working = widget.state.isWorking;
    final actionLabel = working ? '下班打卡' : '上班打卡';
    final toolbarColors = M3EFloatingToolbarColors(
      toolbarContainerColor: colors.surfaceContainerHigh,
      toolbarContentColor: colors.onSurface,
      fabContainerColor: working ? colors.errorContainer : colors.primary,
      fabContentColor: working ? colors.onErrorContainer : colors.onPrimary,
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        height: 80,
        child: Center(
          child: M3EFabHorizontalFloatingToolbar(
            expanded: true,
            fabPosition: M3EFloatingToolbarHorizontalFabPosition.end,
            tooltip: '$actionLabel，需要生物识别',
            decoration: M3EFloatingToolbarDecoration(
              colors: toolbarColors,
              motion: M3EMotion.expressiveSpatialFast,
              expandedShadowElevation: 3,
              shape: const StadiumBorder(),
            ),
            content: SizedBox(
              width: 188,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: ShapeDecoration(
                      color: colors.surfaceContainerHighest,
                      shape: const CircleBorder(),
                    ),
                    child: Icon(
                      widget.biometricAvailable
                          ? Icons.fingerprint_rounded
                          : Icons.gpp_maybe_rounded,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          actionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          widget.biometricAvailable ? '轻触并验证身份' : '需先配置生物识别',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: FloatingActionButton(
                heroTag: null,
                onPressed: widget.isSubmitting ? null : _submit,
                tooltip: actionLabel,
                elevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                highlightElevation: 0,
                backgroundColor: toolbarColors.fabContainerColor,
                foregroundColor: toolbarColors.fabContentColor,
                shape: working
                    ? RoundedRectangleBorder(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(7),
                        ),
                      )
                    : const CircleBorder(),
                child: widget.isSubmitting
                    ? ExpressiveLoadingIndicator(
                        color: toolbarColors.fabContentColor,
                        size: 34,
                        semanticsLabel: '正在提交打卡',
                      )
                    : AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: child,
                          );
                        },
                        child: Icon(
                          working
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(working),
                          size: 30,
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
