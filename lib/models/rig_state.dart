// lib/models/rig_state.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';

int? _i(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class RigState extends ChangeNotifier {
  // Sensors
  double rpm     = 0;
  double _rawRpm = 0;
  double current = 0;
  double temp    = 0;
  double tempAvg = 0;
  int    tempTrend = 0;
  double gx = 0, gy = 0, gz = 0;

  double vibRms = 0;
  double misMag = 0;

  // Vibration
  bool vibRaw      = false;
  bool almVibration = false;
  bool get vibActive => vibRaw || almVibration;

  // Device echo
  bool motorOn   = false;
  int  motorSpeed = 0;          // RPM, 0-210
  bool fanOn     = false;
  bool ledOn     = false;
  bool buzzerOn  = false;
  int  servoAngle = 20;
  bool manualMode = false;

  // Fault flags
  bool almOverheat    = false;
  bool almOvercurrent = false;
  bool almMisalign    = false;
  bool inFault        = false;
  String faultCode    = 'NONE';

  int sevOverheat    = 0;
  int sevOvercurrent = 0;
  int sevVibration   = 0;
  int sevMisalign    = 0;

  bool get anyAlarm => almOverheat || almOvercurrent || almVibration || almMisalign;

  // Only OVERHEAT physically stops the motor now (firmware-side).
  // Overcurrent is informational/flag-only.
  bool get isCritical => almOverheat;

  int get maxSeverity {
    int m = 0;
    if (sevOverheat    > m) m = sevOverheat;
    if (sevOvercurrent > m) m = sevOvercurrent;
    if (sevVibration   > m) m = sevVibration;
    if (sevMisalign    > m) m = sevMisalign;
    return m;
  }

  bool      connected  = false;
  DateTime? lastUpdate;

  // Local manual control state (RPM)
  bool localManual    = false;
  bool localMotorOn   = false;
  int  localMotorSpeed = 0;     // RPM target
  bool localFanOn     = false;
  bool localLedOn     = false;
  bool localBuzzerOn  = false;
  int  localServoAngle = 20;

  bool testMode = false;

  // Kept for backward compatibility with dashboard_screen.dart.
  // No longer used (overcurrent is flag-only now), but the setter must exist
  // so existing UI code that registers a callback still compiles.
  void Function(String)? onEmergencyCommand;

  void updateFromJson(Map<String, dynamic> j) {
    _rawRpm = _d(j['r']) ?? _rawRpm;
    rpm = (localManual && localMotorOn) ? localMotorSpeed.toDouble() : _rawRpm;

    current = _d(j['c']) ?? current;
    temp    = _d(j['t']) ?? temp;

    tempAvg   = _d(j['t_avg'])   ?? temp;
    tempTrend = _i(j['t_trend']) ?? 0;

    gx = _d(j['x']) ?? gx;
    gy = _d(j['y']) ?? gy;
    gz = _d(j['z']) ?? gz;

    vibRms = _d(j['vib_rms']) ?? vibRms;
    misMag = _d(j['mis_mag']) ?? misMag;

    vibRaw       = _i(j['v'])       == 1;
    almVibration = _i(j['alm_vib']) == 1;

    motorOn    = _i(j['m'])      == 1;
    motorSpeed = _i(j['spd'])    ?? motorSpeed;     // RPM
    fanOn      = _i(j['f'])      == 1;
    ledOn      = _i(j['l'])      == 1;
    buzzerOn   = _i(j['b'])      == 1;
    servoAngle = _i(j['s'])      ?? servoAngle;
    manualMode = _i(j['manual']) == 1;
    inFault    = _i(j['fault'])  == 1;
    testMode   = _i(j['test'])   == 1;

    almOverheat    = _i(j['alm_ov'])  == 1;
    almOvercurrent = _i(j['alm_oc'])  == 1;
    almMisalign    = _i(j['alm_mis']) == 1;

    sevOverheat    = _i(j['alm_sev_ov'])  ?? 0;
    sevOvercurrent = _i(j['alm_sev_oc'])  ?? 0;
    sevVibration   = _i(j['alm_sev_vib']) ?? 0;
    sevMisalign    = _i(j['alm_sev_mis']) ?? 0;

    faultCode = (j['fault_code'] as String?) ?? 'NONE';

    lastUpdate = DateTime.now();
    notifyListeners();
  }

  void setConnected(bool v) {
    connected = v;
    notifyListeners();
  }

  void syncLocalToDevice() {
    localMotorOn    = motorOn;
    localMotorSpeed = motorSpeed.clamp(0, 210);
    localFanOn      = fanOn;
    localLedOn      = ledOn;
    localBuzzerOn   = buzzerOn;
    localServoAngle = servoAngle;
    notifyListeners();
  }

  void updateManualRpm() {
    if (localManual && localMotorOn) {
      rpm = localMotorSpeed.toDouble();
      notifyListeners();
    }
  }

  String buildStartTestCommand() {
    localManual     = false;
    localMotorOn    = true;
    localMotorSpeed = 210;
    return jsonEncode({
      'manual': 0,
      'm':      1,
      'spd':    210,            // RPM target
      'f':      0,
      'b':      0,
      's':      localServoAngle,
      'test':   1,
    });
  }

  String buildStopTestCommand() {
    localMotorOn    = false;
    localMotorSpeed = 0;
    return jsonEncode({
      'manual': localManual ? 1 : 0,
      'm':      0,
      'spd':    0,
      'f':      0,
      'b':      0,
      's':      localServoAngle,
      'test':   0,
    });
  }

  // 'spd' is interpreted by the firmware as TARGET RPM (0-210).
  String buildCommand() => jsonEncode({
    'manual': localManual ? 1 : 0,
    'm':      localMotorOn ? 1 : 0,
    'spd':    localMotorSpeed,
    'f':      localFanOn ? 1 : 0,
    'l':      localLedOn ? 1 : 0,
    'b':      localBuzzerOn ? 1 : 0,
    's':      localServoAngle,
  });
}
