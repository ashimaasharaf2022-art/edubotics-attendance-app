import 'dart:math';
import 'package:flutter/material.dart';

/// Draws the large glowing gradient ring used on the dashboard hero card.
/// [progress] is 0..1 (fraction of the shift elapsed).
class ShiftRingPainter extends CustomPainter {
  final double progress;
  ShiftRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width / 2) - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final clamped = progress.clamp(0.0, 1.0);
    final sweepAngle = 2 * pi * clamped;
    if (sweepAngle > 0) {
      final arcPaint = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * pi,
          transform: const GradientRotation(-pi / 2),
          colors: const [Color(0xFF38BDF8), Color(0xFF6366F1), Color(0xFFD946EF)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -pi / 2, sweepAngle, false, arcPaint);

      final angle = -pi / 2 + sweepAngle;
      final dotCenter = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
      final glow = Paint()
        ..color = Colors.white.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(dotCenter, 9, glow);
      final dot = Paint()..color = Colors.white;
      canvas.drawCircle(dotCenter, 5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant ShiftRingPainter oldDelegate) => oldDelegate.progress != progress;
}

/// Small percentage ring used on the monthly stat cards.
class PercentRingPainter extends CustomPainter {
  final double percent;
  final Color color;
  PercentRingPainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width / 2) - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, track);

    final clamped = percent.clamp(0.0, 1.0);
    final sweepAngle = 2 * pi * clamped;
    if (sweepAngle > 0) {
      final fg = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -pi / 2, sweepAngle, false, fg);
    }
  }

  @override
  bool shouldRepaint(covariant PercentRingPainter oldDelegate) => oldDelegate.percent != percent || oldDelegate.color != color;
}