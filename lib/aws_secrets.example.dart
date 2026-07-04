// lib/aws_secrets.example.dart
//
// Copy this file to lib/aws_secrets.dart and fill in your own AWS IoT
// endpoint and certificate/key. lib/aws_secrets.dart is gitignored and
// must never be committed.
//
// IMPORTANT: if you previously had real credentials committed to this
// repo, treat them as compromised — revoke/deactivate that certificate in
// AWS IoT Core -> Security -> Certificates and issue a new one before
// using it here.

class AwsSecrets {
  static const String host = 'YOUR_ENDPOINT.iot.YOUR_REGION.amazonaws.com';

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
