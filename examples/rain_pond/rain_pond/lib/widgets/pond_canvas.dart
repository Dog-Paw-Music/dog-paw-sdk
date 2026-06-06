import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controllers/pond_controller.dart';
import 'water_painter.dart';

/// Drives a steady ticker and paints the pond via [WaterPainter].
class PondCanvas extends StatefulWidget {
  const PondCanvas({super.key, required this.controller});

  final PondController controller;

  @override
  State<PondCanvas> createState() => _PondCanvasState();
}

class _PondCanvasState extends State<PondCanvas> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final Duration dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    if (dt > Duration.zero) {
      widget.controller.advance(dt);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Size sz = Size(c.maxWidth, c.maxHeight);
        widget.controller.setCanvasSize(sz);
        return CustomPaint(
          painter: WaterPainter(controller: widget.controller),
          size: sz,
        );
      },
    );
  }
}
