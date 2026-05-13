// lib/widgets/manual_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/rig_state.dart';
import '../theme.dart';

class ManualPanel extends StatelessWidget {
  final void Function(String cmd) onSend;

  const ManualPanel({super.key, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RigState>();

    return Container(
      decoration: BoxDecoration(
        color: state.localManual ? const Color(0xFF0A1E2E) : RigTheme.card,
        border: Border.all(
          color: state.localManual ? const Color(0xFF00CFFF) : RigTheme.border,
          width: state.localManual ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: state.localManual
            ? [BoxShadow(color: const Color(0xFF00CFFF).withOpacity(0.15), blurRadius: 20, spreadRadius: 2)]
            : null,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.tune, color: state.localManual ? const Color(0xFF00CFFF) : RigTheme.labelColor, size: 18),
              const SizedBox(width: 8),
              Text('MANUAL OVERRIDE', style: RigTheme.sectionTitle),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  final s = context.read<RigState>();
                  s.localManual = !s.localManual;
                  if (s.localManual) s.syncLocalToDevice();
                  onSend(s.buildCommand());
                  s.notifyListeners();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 56, height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: state.localManual ? const Color(0xFF00CFFF) : RigTheme.surface,
                    border: Border.all(color: RigTheme.border),
                  ),
                  child: Stack(children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      left: state.localManual ? 30 : 2, top: 2,
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.localManual ? RigTheme.bg : RigTheme.labelColor,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),

          if (!state.localManual) ...[
            const SizedBox(height: 16),
            Center(child: Text('Enable manual mode to control actuators', style: RigTheme.label.copyWith(fontSize: 11), textAlign: TextAlign.center)),
          ],

          if (state.localManual) ...[
            const SizedBox(height: 16),

            // Motor
            _SectionLabel('MOTOR'),
            Row(
              children: [
                _ToggleChip(
                  label: state.localMotorOn ? 'ON' : 'OFF',
                  active: state.localMotorOn,
                  onTap: () {
                    final s = context.read<RigState>();
                    s.localMotorOn = !s.localMotorOn;
                    if (!s.localMotorOn) { s.localMotorSpeed = 0; s.updateManualRpm(); }
                    onSend(s.buildCommand());
                    s.notifyListeners();
                  },
                  color: RigTheme.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Motor Speed', style: RigTheme.label),
                        Text('${state.localMotorSpeed} RPM',
                          style: RigTheme.monoLarge.copyWith(
                            fontSize: 14,
                            color: state.localMotorOn ? RigTheme.accent : RigTheme.labelColor,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: _sliderTheme(context, RigTheme.accent),
                      child: Slider(
                        value: state.localMotorSpeed.toDouble(),
                        min: 0, max: 210, divisions: 42,
                        onChanged: state.localMotorOn
                            ? (v) {
                                final s = context.read<RigState>();
                                s.localMotorSpeed = v.round();
                                s.updateManualRpm();
                              }
                            : null,
                        onChangeEnd: (v) {
                          final s = context.read<RigState>();
                          s.localMotorSpeed = v.round();
                          s.updateManualRpm();
                          onSend(s.buildCommand());
                        },
                      ),
                    ),
                  ]),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Servo
            _SectionLabel('SERVO ANGLE'),
            Row(
              children: [
                const Icon(Icons.rotate_right, color: Color(0xFF00CFFF), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Angle', style: RigTheme.label),
                        Text('${state.localServoAngle}°',
                          style: RigTheme.monoLarge.copyWith(fontSize: 16, color: const Color(0xFF00CFFF)),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: _sliderTheme(context, const Color(0xFF00CFFF)),
                      child: Slider(
                        value: state.localServoAngle.toDouble(),
                        min: 10, max: 170, divisions: 32,
                        onChanged: (v) { final s = context.read<RigState>(); s.localServoAngle = v.round(); s.notifyListeners(); },
                        onChangeEnd: (v) { final s = context.read<RigState>(); s.localServoAngle = v.round(); onSend(s.buildCommand()); s.notifyListeners(); },
                      ),
                    ),
                  ]),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Fan, LED, Buzzer
            _SectionLabel('AUXILIARIES'),
            Row(
              children: [
                Expanded(
                  child: _ToggleChip(
                    label: 'FAN ${state.localFanOn ? "ON" : "OFF"}',
                    active: state.localFanOn, icon: Icons.air,
                    onTap: () {
                      final s = context.read<RigState>();
                      s.localFanOn = !s.localFanOn;
                      onSend(s.buildCommand());
                      s.notifyListeners();
                    },
                    color: const Color(0xFF44AAFF),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ToggleChip(
                    label: 'LED ${state.localLedOn ? "ON" : "OFF"}',
                    active: state.localLedOn, icon: Icons.lightbulb,
                    onTap: () {
                      final s = context.read<RigState>();
                      s.localLedOn = !s.localLedOn;
                      onSend(s.buildCommand());
                      s.notifyListeners();
                    },
                    color: const Color(0xFFFFE066),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ToggleChip(
                    label: 'BUZZER ${state.localBuzzerOn ? "ON" : "OFF"}',
                    active: state.localBuzzerOn, icon: Icons.notifications_active,
                    onTap: () {
                      final s = context.read<RigState>();
                      s.localBuzzerOn = !s.localBuzzerOn;
                      onSend(s.buildCommand());
                      s.notifyListeners();
                    },
                    color: RigTheme.warning,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context, Color color) {
    return SliderTheme.of(context).copyWith(
      activeTrackColor: color,
      inactiveTrackColor: RigTheme.surface,
      thumbColor: color,
      overlayColor: color.withOpacity(0.2),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: RigTheme.label.copyWith(letterSpacing: 2)),
  );
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  const _ToggleChip({required this.label, required this.active, required this.onTap, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : RigTheme.surface,
          border: Border.all(color: active ? color : RigTheme.border, width: 1.5),
          borderRadius: BorderRadius.circular(6),
          boxShadow: active ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 8, spreadRadius: 1)] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: active ? color : RigTheme.labelColor), const SizedBox(width: 6)],
            Text(label, style: RigTheme.monoLarge.copyWith(fontSize: 10, color: active ? color : RigTheme.labelColor, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
