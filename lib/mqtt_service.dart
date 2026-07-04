// lib/mqtt_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'aws_secrets.dart';

typedef OnMessage = void Function(Map<String, dynamic> json);
typedef OnConnected = void Function(bool connected);

class MqttService {
  static const int _port = 8883;
  static const String _clientId = 'flutter_dashboard';
  static const String _subTopic = 'rig/data';
  static const String _pubTopic = 'rig/cmd';

  MqttServerClient? _client;
  OnMessage? onMessage;
  OnConnected? onConnected;

  Future<void> connect() async {
    _client = MqttServerClient.withPort(AwsSecrets.host, _clientId, _port);
    _client!.secure = true;
    _client!.keepAlivePeriod = 30;
    _client!.autoReconnect = true;
    _client!.logging(on: false);

    final ctx = SecurityContext.defaultContext;
    ctx.setTrustedCertificatesBytes(utf8.encode(AwsSecrets.rootCa));
    ctx.useCertificateChainBytes(utf8.encode(AwsSecrets.deviceCert));
    ctx.usePrivateKeyBytes(utf8.encode(AwsSecrets.privateKey));
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
