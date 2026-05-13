
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <ESP32Servo.h>
#include <Adafruit_MLX90614.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <math.h>
#include <time.h>

// ================= WIFI =================
// ================= WIFI =================
const char* ssid     = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";


static const char* root_ca PROGMEM     = R"(...)";
static const char* device_cert PROGMEM = R"(...)";
static const char* private_key PROGMEM = R"(...)";

// ================= AWS =================
const char* aws_endpoint = "your-endpoint.iot.region.amazonaws.com";
const char* pub_topic    = "rig/data";
const char* sub_topic    = "rig/cmd";

// ================= LAST WILL & TESTAMENT =================
// status_topic carries device online/offline state. The broker will publish
// the WILL message automatically when the ESP32 disconnects ungracefully
// (power loss, WiFi drop, crash, watchdog reset, etc).
//
// QoS 1 = "at least once" — the broker holds the will until a subscriber
// acknowledges it. QoS 0 would let the message vanish if the dashboard is
// momentarily disconnected when the rig dies; that defeats the whole point
// of a will. AWS IoT Core does NOT support QoS 2.
//
// retain=true makes the broker keep the last status message so any dashboard
// that connects later immediately sees the current online/offline state,
// instead of waiting for the next change.
const char* status_topic   = "rig/status";
const char* will_message   = "{\"online\":0,\"reason\":\"unexpected_disconnect\"}";
const char* birth_message  = "{\"online\":1,\"reason\":\"connected\"}";
const char* goodbye_message = "{\"online\":0,\"reason\":\"clean_shutdown\"}";
#define MQTT_STATUS_QOS    1
#define MQTT_STATUS_RETAIN true

// ================= CERTS =================
static const char* root_ca PROGMEM     = R"(...)";
static const char* device_cert PROGMEM = R"(...)";
static const char* private_key PROGMEM = R"(...)";
// ================= PINS =================
#define ENCODER_A    35
#define CURRENT_PIN  34
#define VIB_PIN       5
#define BUZZER_PIN   16
#define SERVO_PIN    13
#define MOTOR_IN1    26
#define MOTOR_IN2    27
#define MOTOR_PWM    18
#define FAN_PIN      14
#define LED_PIN      23

// Relay polarity: this module is ACTIVE-HIGH (fan ON when GPIO is HIGH).
// If you ever swap to an active-LOW relay, change this to 1.
#define FAN_RELAY_ACTIVE_LOW   0
#define FAN_ON_LEVEL  (FAN_RELAY_ACTIVE_LOW ? LOW  : HIGH)
#define FAN_OFF_LEVEL (FAN_RELAY_ACTIVE_LOW ? HIGH : LOW)

// ================= LEDC =================
// 20 kHz is silent but cheap L298Ns can't switch that fast, leaving the
// motor with reduced effective voltage. 8 kHz is still mostly inaudible
// and well within the L298N's switching window.
#define LEDC_FREQ_PWM    8000U
#define LEDC_FREQ_BUZ    2000U
#define LEDC_RES_BITS       8

// ================= ACS712-05B =================
#define ACS712_MV_PER_A   185.0f   // 5A version sensitivity
#define CURRENT_DEADBAND   0.05f   // ignore <50 mA noise after offset

// ================= THRESHOLDS =================
// Overheat — only fault that physically stops the motor
#define TEMP_WARN          35.0f
#define TEMP_TRIP          55.0f
#define TEMP_CLEAR         45.0f
#define TEMP_SEV2          60.0f
#define TEMP_SEV3          70.0f
#define TEMP_AVG_WINDOW    8

// Overcurrent — FLAG ONLY (per spec). Motor does NOT stop.
#define CURRENT_TRIP        0.9f
#define CURRENT_CLEAR       0.7f
#define CURRENT_SEV2        1.2f
#define CURRENT_SEV3        1.5f
#define CURRENT_PERSIST_MS  200

// Vibration — digital pin 5 only, debounced. Flag only.
#define VIB_DEBOUNCE_MS     500

// Misalignment — gyro low-pass magnitude. Flag only.
// Lowered thresholds so flag actually fires on noticeable tilt.
#define MISALIGN_LOW        0.10f
#define MISALIGN_MED        0.20f
#define MISALIGN_HIGH       0.40f
#define MISALIGN_TRIP       0.25f
#define MISALIGN_CLEAR      0.15f
#define MISALIGN_PERSIST_MS 500

#define RPM_MAX             210
#define BUZZER_INTERVAL_MS  400

// Resume cooldown after overheat clears
#define RESUME_DELAY_MS    2000

// (Closed-loop PI removed — direct PWM mapping is used now.)

// ================= FORWARD DECLARATIONS =================
void calibrateCurrent();
void calibrateGyro();
void connectAWS();
void mqttCallback(char* topic, byte* payload, unsigned int len);

// ================= CLIENTS =================
WiFiClientSecure net;
PubSubClient     client(net);

// ================= SENSORS =================
Adafruit_MLX90614 mlx;
Adafruit_MPU6050  mpu;
Servo             servo;

// ================= RUNTIME =================
volatile long          pulses      = 0;
volatile unsigned long lastPulseUs = 0;

float rpmRaw = 0, rpmFiltered = 0;
float current = 0;
float temp    = 0;
float gx=0, gy=0, gz=0;
float gx0=0, gy0=0, gz0=0;

float currentOffsetMv = 1650.0f;   // VCC/2 fallback before calibration

float tempBuf[TEMP_AVG_WINDOW] = {0};
int   tempBufIdx    = 0;
bool  tempBufFilled = false;
float tempAvg  = 0;
float tempPrev = 0;
int   tempTrend = 0;

// Gyro filtering for misalignment + (informational) vibration RMS
float gxLP=0, gyLP=0, gzLP=0;
float gxHP=0, gyHP=0, gzHP=0;
#define HP_WINDOW 16
float hpBuf[HP_WINDOW] = {0};
int   hpBufIdx = 0;
float hpRms = 0;
float lpMag = 0;

// Commanded state (motor auto-starts at full speed, AUTO mode)
bool  manualMode    = false;
bool  motorOn       = true;        // <-- AUTO START
int   targetRpm     = RPM_MAX;     // <-- FULL SPEED on boot
int   manualPwm     = 0;           // PI output in manual mode (0-255)
bool  fanOn         = false;
bool  ledOn         = false;
bool  buzzerOn      = false;
int   servoAngle    = 20;

// Fault flags
bool  flagOverheat    = false;
bool  flagOvercurrent = false;
bool  flagVibration   = false;
bool  flagMisalign    = false;

uint8_t sevOverheat    = 0;
uint8_t sevOvercurrent = 0;
uint8_t sevVibration   = 0;
uint8_t sevMisalign    = 0;

unsigned long currentTripStartMs  = 0;
unsigned long misalignTripStartMs = 0;
unsigned long vibStartMs          = 0;

// Only OVERHEAT triggers this state machine now
enum ResumeState { RS_NORMAL, RS_FAULTED, RS_WAITING };
ResumeState resumeState      = RS_NORMAL;
unsigned long faultClearedMs = 0;
bool  motorWasOn    = false;
int   targetRpmWas  = 0;
const char* faultCode = "NONE";

unsigned long lastBuzzerMs  = 0;
bool buzzerBeepState        = false;

unsigned long lastRPMms    = 0;
unsigned long lastSendms   = 0;
unsigned long lastPiMs     = 0;

float piIntegral = 0;

// ================= NTP =================
void syncNTP() {
  if (WiFi.status() != WL_CONNECTED) return;
  Serial.print("Syncing NTP time...");
  configTime(2 * 3600, 0, "pool.ntp.org", "time.nist.gov", "time.google.com");
  struct tm ti;
  for (int i = 0; i < 40; i++) {
    delay(500);
    Serial.print(".");
    if (getLocalTime(&ti) && ti.tm_year > 120) {
      Serial.printf("\nTime synced: %04d-%02d-%02d %02d:%02d:%02d UTC+2\n",
        ti.tm_year + 1900, ti.tm_mon + 1, ti.tm_mday,
        ti.tm_hour, ti.tm_min, ti.tm_sec);
      return;
    }
  }
  Serial.println("\nWARN: NTP timeout");
}

// ================= WIFI =================
void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  Serial.print("WiFi connecting");
  int tries = 0;
  while (WiFi.status() != WL_CONNECTED && tries < 40) {
    delay(500); Serial.print("."); tries++;
  }
  if (WiFi.status() == WL_CONNECTED) {
    WiFi.setSleep(false);
    Serial.println("\nWiFi OK  IP:" + WiFi.localIP().toString());
    syncNTP();
  } else {
    Serial.println("\nWiFi FAILED");
  }
}

// ================= AWS =================
bool tlsConfigured = false;

void connectAWS() {
  if (WiFi.status() != WL_CONNECTED) {
    WiFi.reconnect();
    unsigned long t0 = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t0 < 10000) delay(500);
    if (WiFi.status() != WL_CONNECTED) return;
    syncNTP();
  }
  struct tm ti;
  if (!getLocalTime(&ti) || ti.tm_year <= 120) syncNTP();

  if (!tlsConfigured) {
    net.setCACert(root_ca);
    net.setCertificate(device_cert);
    net.setPrivateKey(private_key);
    tlsConfigured = true;
  }
  client.setBufferSize(700);
  client.setKeepAlive(30);
  client.setServer(aws_endpoint, 8883);
  client.setCallback(mqttCallback);

  Serial.print("MQTT connecting");
  int attempts = 0;
  while (!client.connected() && attempts < 5) {
    Serial.print(".");
    String clientId = "ESP32_RIG_" + String((uint32_t)ESP.getEfuseMac(), HEX);

    // Connect with Last Will registered.
    // Signature: connect(clientId, willTopic, willQos, willRetain, willMessage)
    bool ok = client.connect(
      clientId.c_str(),
      status_topic,
      MQTT_STATUS_QOS,
      MQTT_STATUS_RETAIN,
      will_message
    );

    if (ok) {
      client.subscribe(sub_topic);

      // Publish the BIRTH message — overwrites any stale "offline" retained
      // message left by the previous session's will.  Same topic/QoS/retain
      // as the will, so any subscriber gets a consistent picture.
      client.publish(status_topic, birth_message, MQTT_STATUS_RETAIN);

      Serial.println(" MQTT OK (will registered, birth published)");
      return;
    }
    char tlsErr[64] = "";
    net.lastError(tlsErr, sizeof(tlsErr));
    Serial.printf(" state=%d err='%s'\n", client.state(), tlsErr);
    delay(2000 * (attempts + 1));
    attempts++;
  }
}

// ================= JSON HELPER =================
static int parseIntField(const String& msg, int keyIdx, int keyLen) {
  int v = keyIdx + keyLen;
  while (v < (int)msg.length() && (msg[v] == ' ' || msg[v] == '\t')) v++;
  int sign = 1;
  if (v < (int)msg.length() && msg[v] == '-') { sign = -1; v++; }
  long val = 0;
  bool got = false;
  while (v < (int)msg.length() && isdigit(msg[v])) {
    val = val * 10 + (msg[v] - '0'); got = true; v++;
  }
  return got ? (int)(sign * val) : 0;
}

// ================= MQTT CALLBACK =================
void mqttCallback(char* topic, byte* payload, unsigned int len) {
  String msg = "";
  for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
  Serial.println("CMD: " + msg);

  bool overheatLockout = (resumeState != RS_NORMAL);

  int idx;

  // --- Manual override flag: this is the GATEKEEPER ---
  // In AUTO mode, the firmware ignores dashboard m/spd commands so the
  // auto-start at full RPM stays sticky. Only when the user explicitly
  // enables manual override does the dashboard get to drive m/spd/etc.
  idx = msg.indexOf("\"manual\":");
  if (idx >= 0) {
    bool newManual = (parseIntField(msg, idx, 9) == 1);
    if (newManual != manualMode) {
      piIntegral = 0;   // avoid wind-up bumps on mode change
      if (!newManual) {
        // Switching back to AUTO: restore full-speed running
        motorOn   = true;
        targetRpm = RPM_MAX;
        Serial.println("Manual OFF -> AUTO full speed");
      } else {
        Serial.println("Manual ON -> dashboard now controls motor");
      }
    }
    manualMode = newManual;
  }

  // m and spd are ONLY honored while manualMode is true.
  // In auto mode the firmware decides (full RPM, stop only on overheat).
  if (manualMode) {
    idx = msg.indexOf("\"m\":");
    if (idx >= 0) {
      int v = parseIntField(msg, idx, 4);
      if (!overheatLockout) motorOn = (v == 1);
    }

    idx = msg.indexOf("\"spd\":");
    if (idx >= 0 && !overheatLockout) {
      targetRpm = constrain(parseIntField(msg, idx, 6), 0, RPM_MAX);
      if (targetRpm == 0) piIntegral = 0;
      Serial.printf("CMD targetRPM=%d\n", targetRpm);
    }
  }

  idx = msg.indexOf("\"f\":");
  if (idx >= 0) fanOn = (parseIntField(msg, idx, 4) == 1);

  idx = msg.indexOf("\"l\":");
  if (idx >= 0) ledOn = (parseIntField(msg, idx, 4) == 1);

  idx = msg.indexOf("\"b\":");
  if (idx >= 0) buzzerOn = (parseIntField(msg, idx, 4) == 1);

  idx = msg.indexOf("\"s\":");
  if (idx >= 0) servoAngle = constrain(parseIntField(msg, idx, 4), 10, 170);
}

// ================= LEDC HELPERS =================
void motorPwmWrite(uint8_t duty) { ledcWrite(MOTOR_PWM, duty); }

bool buzzerAttached = false;
void ensureBuzzerAttached() {
  if (!buzzerAttached) {
    ledcAttach(BUZZER_PIN, LEDC_FREQ_BUZ, LEDC_RES_BITS);
    buzzerAttached = true;
  }
}
void buzzerTone(uint32_t f) { ensureBuzzerAttached(); ledcWriteTone(BUZZER_PIN, f); }
void buzzerOff()            { if (buzzerAttached) ledcWriteTone(BUZZER_PIN, 0); }

// ================= ISR =================
void IRAM_ATTR encoderISR() {
  unsigned long now = micros();
  if (now - lastPulseUs > 1500) {
    pulses++;
    lastPulseUs = now;
  }
}

// ================= SENSOR READS =================
void readRPM() {
  if (millis() - lastRPMms < 1000) return;
  lastRPMms = millis();
  noInterrupts();
  long p = pulses; pulses = 0;
  interrupts();
  rpmRaw      = (p * 60.0f) / 48.0f;
  rpmRaw      = min(rpmRaw, (float)RPM_MAX);
  rpmFiltered = rpmFiltered * 0.7f + rpmRaw * 0.3f;
}

// FIX: factory-calibrated reading instead of bogus linear table
void readCurrent() {
  long sumMv = 0;
  const int N = 200;
  for (int i = 0; i < N; i++) {
    sumMv += analogReadMilliVolts(CURRENT_PIN);
    delayMicroseconds(100);
  }
  float mv  = (float)sumMv / (float)N;
  float raw = (mv - currentOffsetMv) / ACS712_MV_PER_A;
  raw = fabsf(raw);
  current = (raw < CURRENT_DEADBAND) ? 0.0f : raw;
}

void readTemp() {
  float t = mlx.readObjectTempC();
  if (isnan(t) || t < -40.0f || t > 200.0f) return;
  tempPrev = temp;
  temp     = t;
  tempBuf[tempBufIdx] = t;
  tempBufIdx = (tempBufIdx + 1) % TEMP_AVG_WINDOW;
  if (tempBufIdx == 0) tempBufFilled = true;
  int n = tempBufFilled ? TEMP_AVG_WINDOW : max(tempBufIdx, 1);
  float sum = 0;
  for (int i = 0; i < n; i++) sum += tempBuf[i];
  tempAvg = sum / n;
  int trendIdx = (tempBufIdx - 4 + TEMP_AVG_WINDOW) % TEMP_AVG_WINDOW;
  float delta  = t - tempBuf[trendIdx];
  if      (delta >  0.3f) tempTrend =  1;
  else if (delta < -0.3f) tempTrend = -1;
  else                    tempTrend =  0;
}

void readGyro() {
  sensors_event_t a, g, t;
  mpu.getEvent(&a, &g, &t);
  gx = g.gyro.x - gx0;
  gy = g.gyro.y - gy0;
  gz = g.gyro.z - gz0;
  const float alpha = 0.05f;
  gxLP = gxLP * (1.0f - alpha) + gx * alpha;
  gyLP = gyLP * (1.0f - alpha) + gy * alpha;
  gzLP = gzLP * (1.0f - alpha) + gz * alpha;
  lpMag = sqrtf(gxLP*gxLP + gyLP*gyLP + gzLP*gzLP);
  gxHP = gx - gxLP;
  gyHP = gy - gyLP;
  gzHP = gz - gzLP;
  float hpMag = sqrtf(gxHP*gxHP + gyHP*gyHP + gzHP*gzHP);
  hpBuf[hpBufIdx] = hpMag * hpMag;
  hpBufIdx = (hpBufIdx + 1) % HP_WINDOW;
  float sumSq = 0;
  for (int i = 0; i < HP_WINDOW; i++) sumSq += hpBuf[i];
  hpRms = sqrtf(sumSq / HP_WINDOW);
}

// ================= FAULTS =================
void updateFaults() {
  unsigned long now = millis();

  // ---- OVERHEAT — always evaluated, hard-stops motor ----
  if (!flagOverheat && tempAvg >= TEMP_TRIP)      flagOverheat = true;
  else if (flagOverheat && tempAvg <= TEMP_CLEAR) flagOverheat = false;

  if      (tempAvg >= TEMP_SEV3) sevOverheat = 3;
  else if (tempAvg >= TEMP_SEV2) sevOverheat = 2;
  else if (tempAvg >= TEMP_TRIP) sevOverheat = 1;
  else if (tempAvg >= TEMP_WARN) sevOverheat = 1;
  else                           sevOverheat = 0;

  // ---- OVERCURRENT — flag only ----
  bool overInstant = (current >= CURRENT_TRIP);
  if (overInstant) {
    if (currentTripStartMs == 0) currentTripStartMs = now;
    if (!flagOvercurrent && (now - currentTripStartMs >= CURRENT_PERSIST_MS))
      flagOvercurrent = true;
  } else {
    currentTripStartMs = 0;
    if (flagOvercurrent && current <= CURRENT_CLEAR) flagOvercurrent = false;
  }
  if      (current >= CURRENT_SEV3) sevOvercurrent = 3;
  else if (current >= CURRENT_SEV2) sevOvercurrent = 2;
  else if (current >= CURRENT_TRIP) sevOvercurrent = 1;
  else if (flagOvercurrent)         sevOvercurrent = 1;
  else                              sevOvercurrent = 0;

  // ---- VIBRATION — digital pin 5: count pulses in a sliding window ----
  // SW-420 and similar sensors emit BRIEF pulses when shaken, not sustained
  // levels. We count edges over a 1-second window; >= VIB_PULSE_THRESHOLD
  // pulses in that window means "vibrating".
  static unsigned long vibPulseTimestamps[16] = {0};
  static int           vibPulseIdx = 0;
  static int           vibLastPinState = LOW;

  int vibPinNow = digitalRead(VIB_PIN);
  // Detect any edge (HIGH->LOW or LOW->HIGH) — both directions count
  if (vibPinNow != vibLastPinState) {
    vibPulseTimestamps[vibPulseIdx] = now;
    vibPulseIdx = (vibPulseIdx + 1) % 16;
    vibLastPinState = vibPinNow;
  }

  // Count edges that occurred within the last 1000 ms
  int recentPulses = 0;
  for (int i = 0; i < 16; i++) {
    if (vibPulseTimestamps[i] > 0 && (now - vibPulseTimestamps[i]) < 1000) {
      recentPulses++;
    }
  }

  // 3+ edges in 1s = vibrating.  0 edges in 1s = clear.
  if (recentPulses >= 3) {
    flagVibration = true;
    vibStartMs    = now;       // remember when we last saw activity
  } else if (recentPulses == 0 && (now - vibStartMs) > VIB_DEBOUNCE_MS) {
    flagVibration = false;
  }
  sevVibration = flagVibration ? (recentPulses >= 8 ? 2 : 1) : 0;

  // Debug — log vibration status every 2s when there's any activity
  static unsigned long lastVibLog = 0;
  if ((recentPulses > 0 || flagVibration) && now - lastVibLog > 2000) {
    lastVibLog = now;
    Serial.printf("[VIB] pin=%d  pulses_in_1s=%d  flag=%d\n",
                  vibPinNow, recentPulses, flagVibration);
  }

  // ---- MISALIGN — gyro low-pass magnitude. Flag only. ----
  bool misInstant = (lpMag >= MISALIGN_TRIP);
  if (misInstant) {
    if (misalignTripStartMs == 0) misalignTripStartMs = now;
    if (!flagMisalign && (now - misalignTripStartMs >= MISALIGN_PERSIST_MS))
      flagMisalign = true;
  } else {
    misalignTripStartMs = 0;
    if (flagMisalign && lpMag <= MISALIGN_CLEAR) flagMisalign = false;
  }
  if      (lpMag >= MISALIGN_HIGH) sevMisalign = 3;
  else if (lpMag >= MISALIGN_MED)  sevMisalign = 2;
  else if (lpMag >= MISALIGN_LOW)  sevMisalign = 1;
  else                             sevMisalign = 0;
}

// Only OVERHEAT can stop the motor now
void handleFaultResume() {
  bool critical = flagOverheat;

  switch (resumeState) {
    case RS_NORMAL:
      if (critical) {
        motorWasOn   = motorOn;
        targetRpmWas = targetRpm;
        motorOn      = false;
        targetRpm    = 0;
        piIntegral   = 0;
        resumeState  = RS_FAULTED;
        faultCode    = "OVERHEAT";
        Serial.println("FAULT: OVERHEAT — motor stopped");
      }
      break;

    case RS_FAULTED:
      motorOn   = false;
      targetRpm = 0;
      if (!critical && tempAvg <= TEMP_CLEAR) {
        faultClearedMs = millis();
        resumeState    = RS_WAITING;
        Serial.println("Overheat cleared, cooling down...");
      }
      break;

    case RS_WAITING:
      motorOn   = false;
      targetRpm = 0;
      if (critical) {
        resumeState = RS_FAULTED;
      } else if (millis() - faultClearedMs >= RESUME_DELAY_MS) {
        motorOn     = motorWasOn;
        targetRpm   = targetRpmWas;
        resumeState = RS_NORMAL;
        faultCode   = "NONE";
        Serial.println("RESUMED");
      }
      break;
  }
}

// ================= DIRECT PWM (no closed loop) =================
// Slider value (0-210) maps directly to PWM duty (0-255).
// AUTO mode = PWM 255 (full power, same as the diagnostic that worked).
//
// OVERCURRENT THROTTLE: a slow software ceiling that drops PWM when
// current exceeds CURRENT_TRIP and lets it recover when below CURRENT_CLEAR.
// Result: motor self-regulates near the 1.2A limit instead of blindly stalling.
float pwmCeiling = 255.0f;     // dynamic upper bound; persists across calls

int targetToPwm(int target) {
  if (target <= 0) return 0;
  // Map 1..210 to 80..255 so the motor always gets enough duty to spin
  int pwm = map(target, 1, 210, 80, 255);
  if (pwm < 80)  pwm = 80;
  if (pwm > 255) pwm = 255;

  // --- Overcurrent soft cap ---
  if (current > CURRENT_TRIP) {
    // Reduce ceiling proportionally to how far we're over
    float over = current - CURRENT_TRIP;
    pwmCeiling -= 2.0f + over * 30.0f;     // bigger overshoot -> faster cut
    if (pwmCeiling < 80.0f) pwmCeiling = 80.0f;   // never below stiction
  } else if (current < CURRENT_CLEAR) {
    // Slowly relax the ceiling back up to allow recovery
    pwmCeiling += 1.0f;
    if (pwmCeiling > 255.0f) pwmCeiling = 255.0f;
  }
  // Between CLEAR and TRIP: hold ceiling steady (hysteresis)

  if (pwm > (int)pwmCeiling) pwm = (int)pwmCeiling;
  return pwm;
}

// ================= ACTUATORS =================
void motorControl() {
  // L298N: forward = IN1 HIGH, IN2 LOW.  Stop = both LOW + PWM 0 (coast).
  if (!motorOn || resumeState != RS_NORMAL || targetRpm <= 0) {
    digitalWrite(MOTOR_IN1, LOW);
    digitalWrite(MOTOR_IN2, LOW);
    motorPwmWrite(0);
    return;
  }
  digitalWrite(MOTOR_IN1, HIGH);
  digitalWrite(MOTOR_IN2, LOW);

  int pwm = targetToPwm(targetRpm);
  manualPwm = pwm;
  motorPwmWrite((uint8_t)pwm);

  // Debug print: once per second, show what we're commanding
  static unsigned long lastDbg = 0;
  if (millis() - lastDbg > 1000) {
    lastDbg = millis();
    Serial.printf("[MOTOR] on=%d target=%d  rpmFilt=%.1f  PWM=%d (%.0f%%)  ceil=%.0f  I=%.2fA\n",
                  motorOn, targetRpm, rpmFiltered, pwm, pwm * 100.0f / 255.0f,
                  pwmCeiling, current);
  }
}

void thermalControl() {
  static unsigned long lastLedBlinkMs = 0;
  static bool ledBlinkState = false;
  static unsigned long lastFanLog = 0;
  static bool autoFanLatch = false;

  // Persistence-based hysteresis: tempAvg must STAY above/below the
  // threshold for FAN_PERSIST_MS before the fan state actually flips.
  // This kills the random on/off behaviour that happens when the temp
  // reading bounces across 35.0 due to sensor noise.
  static unsigned long aboveTripStartMs = 0;
  static unsigned long belowClearStartMs = 0;
  const unsigned long FAN_PERSIST_MS = 1500;
  const float FAN_TRIP  = TEMP_WARN;            // 35.0 °C  -> turn on
  const float FAN_CLEAR = TEMP_WARN - 5.0f;     // 30.0 °C  -> turn off

  unsigned long now = millis();

  if (tempAvg >= FAN_TRIP) {
    if (aboveTripStartMs == 0) aboveTripStartMs = now;
    belowClearStartMs = 0;
    if (!autoFanLatch && (now - aboveTripStartMs) >= FAN_PERSIST_MS) {
      autoFanLatch = true;
    }
  } else if (tempAvg < FAN_CLEAR) {
    if (belowClearStartMs == 0) belowClearStartMs = now;
    aboveTripStartMs = 0;
    if (autoFanLatch && (now - belowClearStartMs) >= FAN_PERSIST_MS) {
      autoFanLatch = false;
    }
  } else {
    // In hysteresis band — hold current state, reset both timers
    aboveTripStartMs = 0;
    belowClearStartMs = 0;
  }

  bool autoFanWantsOn = autoFanLatch || flagOverheat;

  // ---- COMBINE WITH MANUAL OVERRIDE ----
  // Rule: auto fan logic always runs. In manual mode, the user can FORCE the
  // fan ON (dashboard toggle wins over auto saying "off"), but the user
  // CANNOT force the fan OFF when auto safety cooling demands it on. This
  // protects the motor from operator error during overheat conditions.
  bool fanShouldRun;
  if (manualMode) {
    fanShouldRun = fanOn || autoFanWantsOn;
  } else {
    fanShouldRun = autoFanWantsOn;
    fanOn = autoFanWantsOn;   // reflect actual state in published telemetry
  }
  digitalWrite(FAN_PIN, fanShouldRun ? FAN_ON_LEVEL : FAN_OFF_LEVEL);

  // ---- LED ----
  if (manualMode) {
    // Blink in manual mode for visual indication
    if (millis() - lastLedBlinkMs >= 400) {
      lastLedBlinkMs = millis();
      ledBlinkState  = !ledBlinkState;
    }
    digitalWrite(LED_PIN, ledBlinkState ? HIGH : LOW);
    ledOn = ledBlinkState;
  } else {
    // Solid on for any fault, off otherwise
    bool anyFault = flagOverheat || flagOvercurrent || flagVibration || flagMisalign;
    ledOn = anyFault;
    digitalWrite(LED_PIN, anyFault ? HIGH : LOW);
  }

  // Debug: log fan state every 3 seconds (with both temp and tempAvg so we
  // can see whether the source is sensor jitter vs real changes)
  if (millis() - lastFanLog > 3000) {
    lastFanLog = millis();
    Serial.printf("[FAN] run=%d latch=%d auto=%d userToggle=%d manual=%d  temp=%.1f tempAvg=%.1f overheat=%d\n",
                  fanShouldRun ? 1 : 0,
                  autoFanLatch ? 1 : 0,
                  autoFanWantsOn ? 1 : 0,
                  fanOn ? 1 : 0,
                  manualMode ? 1 : 0,
                  temp, tempAvg,
                  flagOverheat ? 1 : 0);
  }
}

void buzzerControl() {
  // Any fault flag triggers the buzzer. Overheat is highest priority (fast beep),
  // everything else gets a slower beep. Manual buzzer toggle from dashboard
  // is a steady tone when no fault is active.
  bool faultActive = flagOverheat || flagOvercurrent || flagVibration || flagMisalign;

  if (flagOverheat) {
    // Highest priority — fast 3 kHz beep
    if (millis() - lastBuzzerMs >= BUZZER_INTERVAL_MS) {
      lastBuzzerMs    = millis();
      buzzerBeepState = !buzzerBeepState;
      buzzerBeepState ? buzzerTone(3000) : buzzerOff();
    }
  } else if (faultActive) {
    // Overcurrent / vibration / misalign — slower 2 kHz beep
    if (millis() - lastBuzzerMs >= BUZZER_INTERVAL_MS * 2) {
      lastBuzzerMs    = millis();
      buzzerBeepState = !buzzerBeepState;
      buzzerBeepState ? buzzerTone(2000) : buzzerOff();
    }
  } else if (buzzerOn) {
    // Manual buzzer override from dashboard
    buzzerTone(1000);
  } else {
    buzzerOff();
    buzzerBeepState = false;
  }

  // Debug: log which fault is currently driving the buzzer (rate-limited)
  static unsigned long lastFaultLog = 0;
  if (faultActive && millis() - lastFaultLog > 2000) {
    lastFaultLog = millis();
    Serial.printf("[BUZZER] faults: ov=%d oc=%d vib=%d mis=%d  (lpMag=%.3f)\n",
      flagOverheat, flagOvercurrent, flagVibration, flagMisalign, lpMag);
  }
}

void servoControl() { servo.write(servoAngle); }

// ================= PUBLISH =================
void sendData() {
  if (millis() - lastSendms < 1000) return;
  lastSendms = millis();
  if (!client.connected()) {
    connectAWS();
    if (!client.connected()) return;
  }

  char p[700];
  snprintf(p, sizeof(p),
    "{"
    "\"r\":%.1f,\"c\":%.3f,"
    "\"t\":%.1f,\"t_avg\":%.1f,\"t_trend\":%d,"
    "\"x\":%.4f,\"y\":%.4f,\"z\":%.4f,"
    "\"v\":%d,\"vib_rms\":%.3f,\"mis_mag\":%.3f,"
    "\"m\":%d,\"spd\":%d,\"f\":%d,\"l\":%d,\"s\":%d,\"b\":%d,"
    "\"manual\":%d,\"fault\":%d,\"fault_code\":\"%s\","
    "\"alm_ov\":%d,\"alm_oc\":%d,\"alm_vib\":%d,\"alm_mis\":%d,"
    "\"alm_sev_ov\":%d,\"alm_sev_oc\":%d,\"alm_sev_vib\":%d,\"alm_sev_mis\":%d"
    "}",
    rpmFiltered, current,
    temp, tempAvg, tempTrend,
    gx, gy, gz,
    digitalRead(VIB_PIN), hpRms, lpMag,
    motorOn ? 1 : 0, targetRpm,
    fanOn ? 1 : 0, ledOn ? 1 : 0, servoAngle, buzzerOn ? 1 : 0,
    manualMode ? 1 : 0,
    (resumeState != RS_NORMAL) ? 1 : 0, faultCode,
    flagOverheat    ? 1 : 0,
    flagOvercurrent ? 1 : 0,
    flagVibration   ? 1 : 0,
    flagMisalign    ? 1 : 0,
    sevOverheat, sevOvercurrent, sevVibration, sevMisalign);

  bool ok = client.publish(pub_topic, p);
  Serial.printf("[MQTT %s] %s\n", ok ? "OK" : "FAIL", p);
}

// ================= CALIBRATION =================
void calibrateCurrent() {
  Serial.print("Calibrating current sensor (motor MUST be off)...");
  long sumMv = 0;
  for (int i = 0; i < 400; i++) {
    sumMv += analogReadMilliVolts(CURRENT_PIN);
    delay(2);
  }
  currentOffsetMv = (float)sumMv / 400.0f;
  Serial.printf(" offset = %.1f mV (%.3f V)\n", currentOffsetMv, currentOffsetMv / 1000.0f);

  // Sanity check: ACS712 idle should sit near VCC/2 = 1500-1700 mV on a 3.3V board with divider,
  // or 2400-2600 mV without divider. Anything outside [1200, 2800] is suspicious.
  if (currentOffsetMv < 1200.0f || currentOffsetMv > 2800.0f) {
    Serial.println("WARN: offset looks wrong — check sensor wiring / supply!");
  }
}

void calibrateGyro() {
  Serial.print("Calibrating gyro...");
  sensors_event_t a, g, t;
  float sx=0, sy=0, sz=0;
  for (int i = 0; i < 200; i++) {
    mpu.getEvent(&a, &g, &t);
    sx += g.gyro.x; sy += g.gyro.y; sz += g.gyro.z;
    delay(5);
  }
  gx0 = sx/200.0f; gy0 = sy/200.0f; gz0 = sz/200.0f;
  Serial.printf(" bias=(%.4f, %.4f, %.4f)\n", gx0, gy0, gz0);
}

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(1500);
  Serial.println("\n=== RIG FIRMWARE BOOT (auto-start AUTO @ full RPM) ===");

  Wire.begin(21, 22);

  if (!mlx.begin()) Serial.println("ERROR: MLX90614 not found");
  else              Serial.println("MLX90614 OK");

  if (!mpu.begin()) Serial.println("ERROR: MPU6050 not found");
  else {
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
    mpu.setFilterBandwidth(MPU6050_BAND_10_HZ);
    Serial.println("MPU6050 OK");
  }

  pinMode(ENCODER_A,   INPUT);
  pinMode(CURRENT_PIN, INPUT);
  pinMode(VIB_PIN,     INPUT);   // SW-420 D0 is push-pull (idles HIGH)
  pinMode(MOTOR_IN1,   OUTPUT);
  pinMode(MOTOR_IN2,   OUTPUT);
  pinMode(FAN_PIN,     OUTPUT);
  pinMode(LED_PIN,     OUTPUT);

  // Make sure the H-bridge is in a known SAFE state during calibration
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, LOW);
  digitalWrite(FAN_PIN,   FAN_OFF_LEVEL);
  digitalWrite(LED_PIN,   LOW);

  // --- Servo MUST attach before any other ledcAttach calls.
  // ESP32Servo auto-allocates an LEDC channel and timer; doing this first
  // prevents the motor PWM from accidentally stealing the servo's resources.
  ESP32PWM::allocateTimer(0);   // reserve timer 0 for the servo library
  servo.setPeriodHertz(50);
  servo.attach(SERVO_PIN, 500, 2500);
  servo.write(servoAngle);

  // Motor PWM uses a different timer pair (Core v3 picks one for us)
  ledcAttach(MOTOR_PWM,  LEDC_FREQ_PWM, LEDC_RES_BITS);
  ledcWrite(MOTOR_PWM,   0);
  // FIX: defer buzzer LEDC attach until first use to avoid the buzzer's
  // tone API from interfering with the motor's PWM channel/timer.

  attachInterrupt(digitalPinToInterrupt(ENCODER_A), encoderISR, RISING);

  connectWiFi();
  connectAWS();

  // --- Calibrate BEFORE motor starts so offset is clean ---
  calibrateCurrent();
  calibrateGyro();

  float t0 = mlx.readObjectTempC();
  if (!isnan(t0) && t0 > -40.0f && t0 < 200.0f) {
    for (int i = 0; i < TEMP_AVG_WINDOW; i++) tempBuf[i] = t0;
    tempAvg = t0; temp = t0; tempBufFilled = true;
    Serial.printf("Initial temp: %.1f C\n", t0);
  }

  // Now we're free to spin — confirm the auto-start state
  motorOn   = true;
  manualMode = false;
  targetRpm = RPM_MAX;
  Serial.printf("=== Setup complete. Motor AUTO-STARTING at %d RPM ===\n\n", targetRpm);
}

// ================= LOOP =================
void loop() {
  if (client.connected()) client.loop();

  readRPM();
  readCurrent();
  readTemp();
  readGyro();

  updateFaults();
  handleFaultResume();

  motorControl();
  thermalControl();
  buzzerControl();
  servoControl();

  sendData();
}
