# Motor Test Rig — Real-Time Motor Monitoring Dashboard

**An ESP32-based motor test rig with live sensor monitoring, safety interlocks, and a Flutter dashboard connected over MQTT/AWS IoT Core.**

## Overview

This project pairs a motor test bench (ESP32 firmware) with a cross-platform Flutter dashboard app. The rig continuously measures RPM, current draw, temperature, and vibration/misalignment on a running motor, publishes readings to AWS IoT Core over MQTT, and lets the dashboard send commands back (manual speed control, fan, LED, buzzer, servo) in real time.

## System Architecture

```
┌──────────────┐        MQTT / TLS        ┌───────────────┐        MQTT / TLS        ┌──────────────────┐
│   ESP32 Rig   │ ───── rig/data (pub) ──▶ │  AWS IoT Core  │ ◀── rig/data (sub) ───── │ Flutter Dashboard │
│ (Motor_Rig.ino)│ ◀──── rig/cmd (sub) ──── │   (MQTT broker) │ ──── rig/cmd (pub) ───▶ │  (rig_dashboard)  │
└──────────────┘                          └───────────────┘                          └──────────────────┘
```

## Hardware (`Motor_Rig.ino`)

- **Board:** ESP32
- **Sensors:** MLX90614 (non-contact IR temperature), MPU6050 (gyro/accel for vibration & misalignment), quadrature encoder (RPM), ACS712-05B (current sensing), SW-420 vibration switch
- **Actuators:** DC motor via L298N driver, servo, fan relay, buzzer, status LED
- **Safety logic:** overheat auto-stops the motor with a cooldown/resume state machine; overcurrent, vibration, and misalignment are flagged (not hard faults) with severity levels; a Last Will & Testament MQTT message reports the rig as offline if it disconnects unexpectedly

## Dashboard (`lib/`)

- **Framework:** Flutter (Dart), state managed with `provider`
- **Connectivity:** `mqtt_client` over TLS to AWS IoT Core, subscribing to `rig/data` and publishing to `rig/cmd`
- **Screens/widgets:** live gauges for RPM/current/temperature, fault indicators, manual override controls

## Setup

### Firmware

1. Open `Motor_Rig.ino` in the Arduino IDE (with the ESP32 board package installed).
2. Fill in your WiFi credentials and AWS IoT endpoint/certificates at the top of the file.
3. Flash to the ESP32.

### Dashboard

```bash
git clone https://github.com/Abdelrahmanemad0/Motor_Test_Rig.git
cd Motor_Test_Rig
cp lib/aws_secrets.example.dart lib/aws_secrets.dart   # then fill in your AWS IoT credentials
flutter pub get
flutter run
```

## Security

`lib/aws_secrets.dart` holds your AWS IoT endpoint, root CA, device certificate, and private key. It is **gitignored** and must never be committed — copy `lib/aws_secrets.example.dart` and fill in your own values locally.

> An earlier version of this repo had a real private key and certificate committed in plaintext. That certificate should be treated as compromised: rotate/deactivate it in AWS IoT Core → Security → Certificates and issue a new one before reusing this project.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Firmware | ESP32 (Arduino framework), PubSubClient, ESP32Servo, Adafruit MLX90614/MPU6050 |
| Cloud | AWS IoT Core (MQTT over TLS) |
| Dashboard | Flutter, Dart, `provider`, `mqtt_client` |

## License

MIT — see [`LICENSE`](LICENSE).
