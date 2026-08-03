import 'package:flutter/material.dart';

import '../../core/service_models.dart';

/// A service's state as one glanceable mark. States where something is
/// expected to change on its own (starting, waiting out a self-heal backoff)
/// breathe, so a tile that is working is distinguishable from one that has
/// settled — a static amber dot reads as stuck.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.state, this.size = 10});

  final ServiceState state;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isTransient != widget.state.isTransient) _sync();
  }

  void _sync() {
    if (widget.state.isTransient) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.state.color(Theme.of(context));

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = 0.45 - 0.3 * _pulse.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: glow),
                blurRadius: widget.size * (1.0 + _pulse.value),
                spreadRadius: widget.size * 0.18,
              ),
            ],
          ),
        );
      },
    );
  }
}
