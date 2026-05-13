// lib/mqtt_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

typedef OnMessage = void Function(Map<String, dynamic> json);
typedef OnConnected = void Function(bool connected);

class MqttService {
  static const String _host =
      'a1qokycrjg3u9d-ats.iot.eu-central-1.amazonaws.com';
  static const int _port = 8883;
  static const String _clientId = 'flutter_dashboard';
  static const String _subTopic = 'rig/data';
  static const String _pubTopic = 'rig/cmd';

  static const String _rootCa = '''
-----BEGIN CERTIFICATE-----
MIIDQTCCAimgAwIBAgITBmyfz5m/jAo54vB4ikPmljZbyjANBgkqhkiG9w0BAQsF
ADA5MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6
b24gUm9vdCBDQSAxMB4XDTE1MDUyNjAwMDAwMFoXDTM4MDExNzAwMDAwMFowOTEL
MAkGA1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJv
b3QgQ0EgMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJ4gHHKeNXj
ca9HgFB0fW7Y14h29Jlo91ghYPl0hAEvrAIthtOgQ3pOsqTQNroBvo3bSMgHFzZM
9O6II8c+6zf1tRn4SWiw3te5djgdYZ6k/oI2peVKVuRF4fn9tBb6dNqcmzU5L/qw
IFAGbHrQgLKm+a/sRxmPUDgH3KKHOVj4utWp+UhnMJbulHheb4mjUcAwhmahRWa6
VOujw5H5SNz/0egwLX0tdHA114gk957EWW67c4cX8jJGKLhD+rcdqsq08p8kDi1L
93FcXmn/6pUCyziKrlA4b9v7LWIbxcceVOF34GfID5yHI9Y/QCB/IIDEgEw+OyQm
jgSubJrIqg0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMC
AYYwHQYDVR0OBBYEFIQYzIU07LwMlJQuCFmcx7IQTgoIMA0GCSqGSIb3DQEBCwUA
A4IBAQCY8jdaQZChGsV2USggNiMOruYou6r4lK5IpDB/G/wkjUu0yKGX9rbxenDI
U5PMCCjjmCXPI6T53iHTfIUJrU6adTrCC2qJeHZERxhlbI1Bjjt/msv0tadQ1wUs
N+gDS63pYaACbvXy8MWy7Vu33PqUXHeeE6V/Uq2V8viTO96LXFvKWlJbYK8U90vv
o/ufQJVtMVT8QtPHRh8jrdkPSHCa2XV4cdFyQzR1bldZwgJcJmApzyMZFo6IQ6XU
5MsI+yMRQ+hDKXJioaldXgjUkK642M4UwtBV8ob2xJNDd2ZhwLnoQdeXeGADbkpy
rqXRfboQnoZsG4q5WTP468SQvvG5
-----END CERTIFICATE-----
''';

  static const String _deviceCert = '''
-----BEGIN CERTIFICATE-----
MIIDWTCCAkGgAwIBAgIUeweoWXGcy82IklDPdEGNXadI4rAwDQYJKoZIhvcNAQEL
BQAwTTFLMEkGA1UECwxCQW1hem9uIFdlYiBTZXJ2aWNlcyBPPUFtYXpvbi5jb20g
SW5jLiBMPVNlYXR0bGUgU1Q9V2FzaGluZ3RvbiBDPVVTMB4XDTI2MDUwNzIyMjIz
OVoXDTQ5MTIzMTIzNTk1OVowHjEcMBoGA1UEAwwTQVdTIElvVCBDZXJ0aWZpY2F0
ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMSnoJRIaARqeCtSjNgg
QBWDK/M2CmUJdgs5oIeGnneul5+z6anxcjEluv1vcC178xAS+2yU2rZrpnrPS3T1
upbIoSbzDiBgk/TO8tl5dqz30We5JoBdT/UHkEymfTINo0fmUB+npZoCwKJwE9WQ
zqQ3HtW5IihEgMEpEAruR2JHZ5+SFin/GSlsTzl6ZdPxKZ03DnFbaVff6QjfY7+d
VWIgkeabnm1+Ujx1LIOPxjmphve7Q6jv4Z7Jh3iLSkWuPzmCowT8GDHKF8fEgTrm
ATqj/fhVlnRaLo0v+H8z0skkjT3129vKGubS9sNKJThhSlUb8oJfFR0eKe6cstnr
s8kCAwEAAaNgMF4wHwYDVR0jBBgwFoAUgmu7bBYzcamf1drYX7NQMEarxdYwHQYD
VR0OBBYEFPiy5oPphfSa94Y4mQoXdCKdUh3vMAwGA1UdEwEB/wQCMAAwDgYDVR0P
AQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4IBAQCt5Y35VlE4Nviu+P1TbatcetpZ
kxNu8YxbOaBbF8D49yo6NwisiJO4l0DmNbEcu2wkGDdlbF4uFiqW4Ha+AGdqHD5O
c3r1yA47Pvf85myJx9Ybh8bt67HNEqg0cWz5uWOGB0g5OBBVsOvJ8z3EVLgTAN1T
y9HREU9jfp3RuUMRT83O9iUHX20A7xYgvRFsACshXNZoAB57RJgGrc/AP7wpLXej
94U4xfD1pPh7LBh3clWwGz/x4+AeJbcg7MtZHQ2vtOZH5omVu2OGVegDLUKg7C1g
KE8ndV4T5Hb8EeO2GbbgfZDEfvy0hNmlmQoHIrJO8XZQ1PDZ7f0ltlU99Z/Q
-----END CERTIFICATE-----
''';

  static const String _privateKey = '''
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAxKeglEhoBGp4K1KM2CBAFYMr8zYKZQl2Czmgh4aed66Xn7Pp
qfFyMSW6/W9wLXvzEBL7bJTatmumes9LdPW6lsihJvMOIGCT9M7y2Xl2rPfRZ7km
gF1P9QeQTKZ9Mg2jR+ZQH6elmgLAonAT1ZDOpDce1bkiKESAwSkQCu5HYkdnn5IW
Kf8ZKWxPOXpl0/EpnTcOcVtpV9/pCN9jv51VYiCR5puebX5SPHUsg4/GOamG97tD
qO/hnsmHeItKRa4/OYKjBPwYMcoXx8SBOuYBOqP9+FWWdFoujS/4fzPSySSNPfXb
28oa5tL2w0olOGFKVRvygl8VHR4p7pyy2euzyQIDAQABAoIBACglXFfJLEryfVPC
x3P7qXl6zMca2iZkNw/1lLr2FXWzU8rLjMEfxEMaQ8EnNcxjSGyYo3E4NioVcegS
V4IqBAxyKsvrxI+Bh9LrSJJzBHItKTe2iZCc/Ay2nZO4TUihlhrAfszniZwWQcMn
hDUOGdFWW1ogMEPuMCa+vkKtAC+krnrkvpcL8Qq82496qsWJdJ7jdOK5POztp7uK
M0keQQtKf3jK61LgvKBgoN7H4yjzqRsb5h7KH+inXlS5aXaLmFfV0THvVFIHxFPQ
vGnIs+zuRfUzWeTkTOfl1a/nVE/f5DcW/BxBvdayt0qtrL797yqn/+ha8eKiuXxb
1kF9AoECgYEA4gaozcE6tE3UYG9pPFFH7xbq2/me54nh75+g8idy8VC+zToXrFAw
cLCNMJsJvb3jCkFS+3pUAy1lIWYoDdjEFJKGITPZJ5qrl4FVRrNvbCsE8UaWzvO+
W/FcZly/4FL+8LUR7PQnBnCvfpq9SUEEoYTO6HhS2wujirvqFzqavRECgYEA3rvY
tAGfSmG/RHx0C1TZSpdJnkl3g8+DAOh4Yt+32VA/VKyfa636j1e4vH0lRXLwS3vk
4ZbKlPiImfZ0zEKRq/43ocudoAb/JufygX0qqYq6h2AcmAGIcX9b/QZTL04iAzEF
ZUQY/BNk4+qJPBXF0cTuj8NjEtTeVEj2ypdZ6zkCgYBJ75+8Xp8TZ/o26XrlLjl3
rml5N7iRSPtNZUxCqkDhS2Z+v6gKx9hwpHArHCwdk0X3jtLUTHm66FiSilZD4UqS
6DNUHR/F4sSKtNXuYLfsDE57lnmyjO0SKmvtWB20BbI7jx+kAWHaq3Xc1kVg9xHK
vCTqyqFf4fjHYxz6KEOB4QKBgQCKhfttYEDoKsig2GH3liqZ2GNhvUFGSe2ox+vv
WkHmNqFckQuJFafqNF1hZNekTKqj14buwjB12+hhEMVtL82XUUDaMF904kUXtlO9
MtIwpWYCwcSmyPVJ2TKlt6ROnGJM59T6ORLs20b49KmrI8NnBfp0kMjyMk+fzc0n
DGBRCQKBgQDQdHsFU2uDvfPUXdKOKXgUUv7aJc+VczOxCy/rS/u1UrH0w3T0Ow3R
h4UfBC2LYFZymPv2hVHrpSr9EnwPfP11DWPacGcKOyZhYCetw3EA3Ncr0s8jXLM0
MxJmpMkUOkBiMkJOuI26hJFdrxR5sUrtBPb6l2kU1761tYBHm48NIw==
-----END RSA PRIVATE KEY-----
''';

  MqttServerClient? _client;
  OnMessage? onMessage;
  OnConnected? onConnected;

  Future<void> connect() async {
    _client = MqttServerClient.withPort(_host, _clientId, _port);
    _client!.secure = true;
    _client!.keepAlivePeriod = 30;
    _client!.autoReconnect = true;
    _client!.logging(on: false);

    final ctx = SecurityContext.defaultContext;
    ctx.setTrustedCertificatesBytes(utf8.encode(_rootCa));
    ctx.useCertificateChainBytes(utf8.encode(_deviceCert));
    ctx.usePrivateKeyBytes(utf8.encode(_privateKey));
    _client!.securityContext = ctx;

    _client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onAutoReconnected = _onReconnected;

    try {
      await _client!.connect();
    } catch (e) {
      print('[MQTT] connect error: $e');
      _client!.disconnect();
      onConnected?.call(false);
    }
  }

  void _onConnected() {
    onConnected?.call(true);
    _client!.subscribe(_subTopic, MqttQos.atLeastOnce);
    _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> msgs) {
      final msg = msgs[0].payload as MqttPublishMessage;
      final raw =
          MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        try {
          onMessage?.call(json);
        } catch (e, st) {
          print('[MQTT] onMessage handler error: $e\n$st\nraw=$raw');
        }
      } catch (e) {
        print('[MQTT] jsonDecode failed: $e\nraw=$raw');
      }
    });
  }

  void _onDisconnected() => onConnected?.call(false);
  void _onReconnected() => onConnected?.call(true);

  void publish(String payload) {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    final builder = MqttClientPayloadBuilder()..addString(payload);
    _client!.publishMessage(
        _pubTopic, MqttQos.atLeastOnce, builder.payload!);
  }

  void disconnect() => _client?.disconnect();
}
