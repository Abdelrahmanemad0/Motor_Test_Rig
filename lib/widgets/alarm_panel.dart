// lib/widgets/alarm_panel.dart
import 'package:flutter/material.dart';
import '../theme.dart';

class AlarmPanel extends StatelessWidget {
  final bool overheat;
  final bool overcurrent;
  final bool vibration;   // debounced flag OR raw sensor — either triggers light
  final bool misalign;

  const AlarmPanel({
    super.key,
    required this.overheat,
    required this.overcurrent,
    required this.vibration,
    required this.misalign,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('ALARM PANEL', style: RigTheme.sectionTitle),
        const SizedBox(height: 12),
        _AlarmLight(label: 'OVERHEAT',    active: overheat,    icon: Icons.local_fire_department, color: RigTheme.alarm),
        const SizedBox(height: 8),
        _AlarmLight(label: 'OVERCURRENT', active: overcurrent, icon: Icons.bolt,                  color: RigTheme.alarm),
        const SizedBox(height: 8),
        _AlarmLight(label: 'VIBRATION',   active: vibration,   icon: Icons.vibration,             color: RigTheme.warning,
                    subtitle: vibration ? 'DETECTED' : 'CLEAR'),
        const SizedBox(height: 8),
        _AlarmLight(label: 'MISALIGN',    active: misalign,    icon: Icons.compare_arrows,        color: RigTheme.warning),
      ],
    );
  }
}

class _AlarmLight extends StatefulWidget {
  final String label;
  final bool active;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _AlarmLight({
    required this.label,
    required this.active,
    required this.icon,
    required this.color,
    this.subtitle = '',
  });

  @override
  State<_AlarmLight> createState() => _AlarmLightState();
}

class _AlarmLightState extends State<_AlarmLight> with SingleTickerProviderStateMixin {
  late AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    if (widget.active) _blink.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AlarmLight old) {
    super.didUpdateWidget(old);
    if (widget.active && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!widget.active) {
      _blink.stop();
      _blink.value = 0;
    }
  }

  @override
  void dispose() { _blink.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (_, __) {
        final glow      = widget.active ? (0.5 + _blink.value * 0.5) : 0.0;
        final ledColor  = widget.active ? widget.color.withOpacity(glow) : RigTheme.surface;
        final textColor = widget.active ? widget.color : RigTheme.labelColor;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: RigTheme.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.active ? widget.color.withOpacity(0.5 + _blink.value * 0.5) : RigTheme.border,
              width: 1,
            ),
            boxShadow: widget.active
                ? [BoxShadow(color: widget.color.withOpacity(0.2 * _blink.value), blurRadius: 12, spreadRadius: 2)]
                : null,
          ),
          child: Row(
            children: [
              // LED dot
              Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ledColor,
                  border: Border.all(color: RigTheme.border, width: 1),
                  boxShadow: widget.active
                      ? [BoxShadow(color: widget.color.withOpacity(0.8 * glow), blurRadius: 8, spreadRadius: 1)]
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Icon(widget.icon, size: 16, color: textColor),
              const SizedBox(width: 8),
              Text(widget.label,
                style: RigTheme.monoLarge.copyWith(fontSize: 12, color: textColor, letterSpacing: 1.5)),
              const Spacer(),
              Text(
                widget.subtitle.isNotEmpty
                    ? widget.subtitle
                    : widget.active ? '⚠ FAULT' : 'NORMAL',
                style: RigTheme.label.copyWith(
                  color: widget.active ? widget.color : const Color(0xFF44FF88),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
