// lib/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rig_state.dart';
import '../mqtt_service.dart';
import '../theme.dart';
import '../widgets/alarm_panel.dart';
import '../widgets/current_bulb.dart';
import '../widgets/gyro_3d.dart';
import '../widgets/manual_panel.dart';
import '../widgets/rpm_gauge.dart';
import '../widgets/thermometer.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final MqttService _mqtt = MqttService();

  @override
  void initState() {
    super.initState();
    final state = context.read<RigState>();

    _mqtt.onConnected = (c) => state.setConnected(c);
    _mqtt.onMessage   = (j) => state.updateFromJson(j);

    state.onEmergencyCommand = (cmd) => _mqtt.publish(cmd);

    _mqtt.connect();
  }

  @override
  void dispose() {
    _mqtt.disconnect();
    super.dispose();
  }

  void _send(String cmd) => _mqtt.publish(cmd);

  void _onStartTest() {
    final s = context.read<RigState>();
    final cmd = s.buildStartTestCommand();
    _send(cmd);
    s.notifyListeners();
  }

  void _onStopTest() {
    final s = context.read<RigState>();
    final cmd = s.buildStopTestCommand();
    _send(cmd);
    s.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RigState>();

    return Scaffold(
      backgroundColor: RigTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(state: state, onStart: _onStartTest, onStop: _onStopTest),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth > 900;
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: _LeftColumn(state: state)),
                          const SizedBox(width: 12),
                          Expanded(flex: 4, child: _CenterColumn(state: state)),
                          const SizedBox(width: 12),
                          Expanded(flex: 3, child: _RightColumn(send: _send)),
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          _CenterColumn(state: state),
                          const SizedBox(height: 12),
                          _LeftColumn(state: state),
                          const SizedBox(height: 12),
                          _RightColumn(send: _send),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header with START/STOP button + status ────────────────────────────────────
class _Header extends StatelessWidget {
  final RigState state;
  final VoidCallback onStart;
  final VoidCallback onStop;
  const _Header({required this.state, required this.onStart, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final running = state.motorOn || state.testMode;
    final faulted = state.inFault || state.isCritical;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: RigTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RigTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.speed, color: RigTheme.accent, size: 22),
          const SizedBox(width: 10),
          Text('RIG DASHBOARD', style: RigTheme.headerFont),
          const SizedBox(width: 16),
          _StatusPill(
            label: state.connected ? 'ONLINE' : 'OFFLINE',
            color: state.connected ? RigTheme.accent : RigTheme.alarm,
          ),
          const SizedBox(width: 8),
          if (faulted)
            _StatusPill(label: 'FAULT: ${state.faultCode}', color: RigTheme.alarm)
          else if (state.testMode)
            _StatusPill(label: 'TEST RUNNING', color: RigTheme.cyan)
          else if (state.manualMode)
            _StatusPill(label: 'MANUAL', color: RigTheme.warning)
          else
            _StatusPill(label: 'IDLE', color: RigTheme.labelColor),
          const Spacer(),
          _StartStopButton(
            running: running,
            disabled: !state.connected || faulted,
            onStart: onStart,
            onStop: onStop,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: RigTheme.label.copyWith(color: color, fontSize: 10, letterSpacing: 1.2),
      ),
    );
  }
}

class _StartStopButton extends StatelessWidget {
  final bool running;
  final bool disabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  const _StartStopButton({
    required this.running,
    required this.disabled,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final color = running ? RigTheme.alarm : RigTheme.accent;
    final label = running ? 'STOP TEST' : 'START TEST';
    final icon  = running ? Icons.stop_rounded : Icons.play_arrow_rounded;

    return GestureDetector(
      onTap: disabled ? null : (running ? onStop : onStart),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: disabled ? RigTheme.surface : color.withOpacity(0.18),
          border: Border.all(color: disabled ? RigTheme.border : color, width: 2),
          borderRadius: BorderRadius.circular(6),
          boxShadow: disabled
              ? null
              : [BoxShadow(color: color.withOpacity(0.35), blurRadius: 14, spreadRadius: 1)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: disabled ? RigTheme.labelColor : color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: RigTheme.monoLarge.copyWith(
                fontSize: 14,
                color: disabled ? RigTheme.labelColor : color,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Left column: temperature + current ────────────────────────────────────────
class _LeftColumn extends StatelessWidget {
  final RigState state;
  const _LeftColumn({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _Card(child: Thermometer(temp: state.tempAvg))),
        const SizedBox(height: 12),
        Expanded(child: _Card(child: CurrentBulb(current: state.current))),
      ],
    );
  }
}

// ─── Center column: RPM gauge + gyro ──────────────────────────────────────────
class _CenterColumn extends StatelessWidget {
  final RigState state;
  const _CenterColumn({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(flex: 3, child: _Card(child: RpmGauge(rpm: state.rpm))),
        const SizedBox(height: 12),
        Expanded(
          flex: 2,
          child: _Card(child: Gyro3D(gx: state.gx, gy: state.gy, gz: state.gz)),
        ),
      ],
    );
  }
}

// ─── Right column: alarms + manual override ───────────────────────────────────
class _RightColumn extends StatelessWidget {
  final void Function(String) send;
  const _RightColumn({required this.send});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RigState>();
    return Column(
      children: [
        _Card(
          child: AlarmPanel(
            overheat:    state.almOverheat,
            overcurrent: state.almOvercurrent,
            vibration:   state.vibActive,
            misalign:    state.almMisalign,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: SingleChildScrollView(child: ManualPanel(onSend: send))),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RigTheme.card,
        border: Border.all(color: RigTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}