import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';

class ExpressiveLoadingIndicator extends StatefulWidget {
  const ExpressiveLoadingIndicator({
    super.key,
    this.size = 40,
    this.color,
    this.semanticsLabel = '正在加载',
  });

  final double size;
  final Color? color;
  final String semanticsLabel;

  @override
  State<ExpressiveLoadingIndicator> createState() =>
      _ExpressiveLoadingIndicatorState();
}

class _ExpressiveLoadingIndicatorState extends State<ExpressiveLoadingIndicator>
    with SingleTickerProviderStateMixin {
  static const _shapes = <Shapes>[
    Shapes.soft_burst,
    Shapes.c9_sided_cookie,
    Shapes.pill,
    Shapes.sunny,
  ];

  late final AnimationController _rotation;
  Timer? _shapeTimer;
  int _shapeIndex = 0;
  bool? _animationsDisabled;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4666),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (_animationsDisabled == disabled) return;
    _animationsDisabled = disabled;
    _shapeTimer?.cancel();
    if (disabled) {
      _rotation.stop();
      _rotation.value = 0;
      return;
    }
    _rotation.repeat();
    _shapeTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (!mounted) return;
      setState(() => _shapeIndex = (_shapeIndex + 1) % _shapes.length);
    });
  }

  @override
  void dispose() {
    _shapeTimer?.cancel();
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: widget.semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: RotationTransition(
            turns: _rotation,
            child: AnimatedSwitcher(
              duration: _animationsDisabled == true
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: M3EShape(
                _shapes[_shapeIndex],
                key: ValueKey<int>(_shapeIndex),
                width: widget.size,
                height: widget.size,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ContainedExpressiveLoadingIndicator extends StatelessWidget {
  const ContainedExpressiveLoadingIndicator({
    super.key,
    this.size = 64,
    this.containerColor,
    this.indicatorColor,
    this.semanticsLabel = '正在加载',
  });

  final double size;
  final Color? containerColor;
  final Color? indicatorColor;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.18),
      decoration: ShapeDecoration(
        color: containerColor ?? colors.primaryContainer,
        shape: const CircleBorder(),
      ),
      child: ExpressiveLoadingIndicator(
        size: size * 0.64,
        color: indicatorColor ?? colors.onPrimaryContainer,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}

class ExpressiveWavyProgressIndicator extends StatefulWidget {
  const ExpressiveWavyProgressIndicator({
    super.key,
    required this.value,
    required this.width,
    this.height = 24,
    this.color,
    this.backgroundColor,
    this.animate = true,
  }) : assert(value >= 0 && value <= 1);

  final double value;
  final double width;
  final double height;
  final Color? color;
  final Color? backgroundColor;
  final bool animate;

  @override
  State<ExpressiveWavyProgressIndicator> createState() =>
      _ExpressiveWavyProgressIndicatorState();
}

class _ExpressiveWavyProgressIndicatorState
    extends State<ExpressiveWavyProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase;

  @override
  void initState() {
    super.initState();
    _phase = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate =
        widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (shouldAnimate && !_phase.isAnimating) {
      _phase.repeat();
    } else if (!shouldAnimate && _phase.isAnimating) {
      _phase.stop();
      _phase.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant ExpressiveWavyProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) didChangeDependencies();
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      value: '${(widget.value * 100).round()}%',
      label: '工作时长进度',
      child: ExcludeSemantics(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _phase,
            builder: (context, _) => CustomPaint(
              painter: _WavyProgressPainter(
                progress: widget.value,
                phase: _phase.value,
                color: widget.color ?? colors.primary,
                trackColor:
                    widget.backgroundColor ?? colors.surfaceContainerHighest,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  const _WavyProgressPainter({
    required this.progress,
    required this.phase,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double phase;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final startX = 3.0;
    final endX = math.max(startX, (size.width - 6) * progress);
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(startX, centerY),
      Offset(size.width - 3, centerY),
      trackPaint,
    );

    if (progress <= 0) return;
    final path = Path();
    const wavelength = 18.0;
    final amplitude = progress > 0.96 ? 0.5 : 3.2;
    for (double x = startX; x <= endX; x += 1) {
      final angle = (x / wavelength + phase) * math.pi * 2;
      final y = centerY + math.sin(angle) * amplitude;
      if (x == startX) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(endX, centerY), 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WavyProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}
