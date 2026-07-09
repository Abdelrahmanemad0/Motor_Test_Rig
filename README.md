# Motor Test Rig — ESP32 + Flutter + AWS IoT

A DC motor test rig with real-time telemetry (RPM, current, temperature, vibration, orientation) and closed-loop fault protection, streamed over MQTT/AWS IoT Core to a cross-platform Flutter dashboard.

<p>
  <img alt="ESP32" src="https://img.shields.io/badge/MCU-ESP32-E7352C?logo=espressif&logoColor=white">
  <img alt="Flutter" src="https://img.shields.io/badge/Dashboard-Flutter-02569B?logo=flutter&logoColor=white">
  <img alt="AWS IoT" src="https://img.shields.io/badge/Cloud-AWS%20IoT%20Core-FF9900?logo=amazonaws&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-yellow.svg">
</p>

## Overview

The rig spins a DC motor and continuously measures RPM (quadrature encoder), current draw (ACS712), object temperature (MLX90614 IR sensor), and vibration/orientation (MPU6050 gyro + SW-420 vibration switch). An ESP32 runs the control loop and fault-detection state machine, publishes telemetry to AWS IoT Core over MQTT/TLS every second, and accepts commands (manual speed override, fan, LED, buzzer, servo) from the dashboard. A Flutter app subscribes to the same topic and renders live gauges, a 3D orientation indicator, and an alarm panel.

## Features

- **Real-time telemetry** — RPM, current, object temperature (instant + smoothed average + trend), 3-axis gyro, vibration pulse rate — published over MQTT every second.
- **Automatic fault protection**
  - **Overheat** — hard-stops the motor above a trip temperature, holds it off through a cooldown delay, then auto-resumes at the previous setpoint.
  - **Overcurrent** — a software PWM ceiling backs off proportionally to how far current exceeds the trip threshold, and relaxes gradually as it recovers (self-regulating, not a hard stop).
  - **Vibration & misalignment** — debounced pulse-window detection (vibration) and low-pass-filtered gyro magnitude (misalignment); both flag-only with severity levels.
- **MQTT Last Will & Testament** — the broker publishes an "offline" status automatically if the ESP32 loses power or crashes, so the dashboard always reflects true device state, not a stale "last known good" reading.
- **Auto / Manual modes** — the rig auto-starts at full RPM on boot; the dashboard can switch to manual mode to directly command speed, fan, LED, buzzer, and servo angle. Auto-mode safety logic (e.g. forced cooling fan during overheat) always overrides manual control, so an operator can't accidentally disable protection.
- **Flutter dashboard** — live RPM gauge, current "bulb" indicator, thermometer with trend arrow, animated 3D gyro/orientation widget, alarm panel with severity levels, and a manual control panel.

## Architecture

```
┌────────────────────┐   MQTT/TLS 8883   ┌──────────────────┐   MQTT/TLS 8883   ┌─────────────────────┐
│   ESP32 Rig         │ ─────────────────▶│  AWS IoT Core      │◀───────────────── │  Flutter Dashboard   │
│   Motor_Rig.ino     │                    │  (topics: rig/data,│                    │  (lib/)               │
│   - sensor reads     │◀───────────────── │   rig/cmd, rig/    │ ────────────────▶│  - MQTT subscriber     │
│   - fault state       │   commands         │   status)           │   commands          │  - gauges / alarms      │
│   - PWM/actuator ctrl  │                    └──────────────────┘                    │  - manual override UI   │
└────────────────────┘                                                              └─────────────────────┘
```

The firmware and dashboard are decoupled — both are independent MQTT clients of AWS IoT Core, authenticated with X.509 device certificates. Neither talks to the other directly.

## Hardware

| Component | Purpose | ESP32 Pin |
|---|---|---|
| Quadrature encoder | RPM measurement | GPIO 35 |
| ACS712-05B | Current sensing | GPIO 34 (ADC) |
| SW-420 | Vibration detection | GPIO 5 |
| MPU6050 | Gyro / orientation (I2C) | GPIO 21/22 |
| MLX90614 | Non-contact object temperature (I2C) | GPIO 21/22 |
| L298N | Motor driver (IN1/IN2/PWM) | GPIO 26/27/18 |
| Relay | Cooling fan | GPIO 14 |
| Servo | Physical indicator/actuator | GPIO 13 |
| Buzzer | Audible alarm | GPIO 16 |
| LED | Visual status | GPIO 23 |

## Tech Stack

| Layer | Technology |
|---|---|
| Firmware | Arduino/C++ on ESP32, `PubSubClient`, `Adafruit_MPU6050`, `Adafruit_MLX90614`, `ESP32Servo` |
| Transport | MQTT over TLS (mutual auth via X.509 certs), AWS IoT Core |
| Dashboard | Flutter, `mqtt_client`, `provider`, `google_fonts` |

## Setup

### Firmware (`Motor_Rig.ino`)

1. Open in Arduino IDE with the ESP32 board package installed.
2. Fill in `ssid` / `password` and your AWS IoT endpoint + certificates (root CA, device cert, private key — issued per-device in AWS IoT Core → Security → Certificates). These are placeholders in the committed file; never commit real values.
3. Flash to the ESP32.

### Dashboard (Flutter)

```bash
# 1. Clone
git clone https://github.com/Abdelrahmanemad0/Motor_Test_Rig.git
cd Motor_Test_Rig

# 2. Configure AWS IoT credentials (git-ignored, never committed)
cp lib/aws_config.example.dart lib/aws_config.dart
# edit lib/aws_config.dart with your AWS IoT endpoint, root CA, device cert, and private key

# 3. Install dependencies
flutter pub get

# 4. Run
flutter run
```

## Security Notes

- Both the firmware and the dashboard authenticate to AWS IoT Core with per-device X.509 certificates (mutual TLS) — there are no long-lived API keys.
- Dashboard credentials live in `lib/aws_config.dart`, which is git-ignored; only `lib/aws_config.example.dart` (a placeholder template) is committed.
- Rotate the AWS IoT certificate immediately if a real key is ever accidentally committed, since a public git history entry should be treated as compromised even after the file is later removed.

## Project Structure

```
Motor_Test_Rig/
├── Motor_Rig.ino                  # ESP32 firmware: sensors, fault state machine, MQTT, actuator control
├── lib/
│   ├── main.dart                  # App entry point
│   ├── mqtt_service.dart          # AWS IoT MQTT client (uses lib/aws_config.dart)
│   ├── aws_config.example.dart    # Template for AWS IoT credentials (copy to aws_config.dart)
│   ├── theme.dart
│   ├── models/rig_state.dart      # Shared telemetry/command state (Provider)
│   ├── screens/dashboard_screen.dart
│   └── widgets/                   # rpm_gauge, thermometer, current_bulb, gyro_3d, alarm_panel, manual_panel
└── pubspec.yaml
```

## License

MIT — see [LICENSE](LICENSE).
