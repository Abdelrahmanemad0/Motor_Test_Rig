// lib/aws_config.example.dart
//
// Template for AWS IoT Core connection secrets used by MqttService.
//
// Setup:
//   1. Copy this file to lib/aws_config.dart (which is git-ignored).
//   2. Fill in your AWS IoT endpoint and the certificate/key issued for
//      your device (AWS IoT Core -> Security -> Certificates).
//   3. Never commit lib/aws_config.dart.
class AwsConfig {
  static const String host = 'YOUR_ID-ats.iot.YOUR_REGION.amazonaws.com';

  static const String rootCa = '''
-----BEGIN CERTIFICATE-----
PASTE_AMAZON_ROOT_CA_1_HERE
-----END CERTIFICATE-----
''';

  static const String deviceCert = '''
-----BEGIN CERTIFICATE-----
PASTE_YOUR_DEVICE_CERTIFICATE_HERE
-----END CERTIFICATE-----
''';

  static const String privateKey = '''
-----BEGIN RSA PRIVATE KEY-----
PASTE_YOUR_PRIVATE_KEY_HERE
-----END RSA PRIVATE KEY-----
''';
}
