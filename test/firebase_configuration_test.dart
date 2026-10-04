import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/firebase_options.dart';

void main() {
  final services = File('android/app/google-services.json');

  test(
    'Dart Firebase options match the native Android default app',
    () {
      final config = jsonDecode(services.readAsStringSync()) as Map;
      final project = config['project_info'] as Map;
      final client = (config['client'] as List).cast<Map>().singleWhere(
        (entry) =>
            entry['client_info']['android_client_info']['package_name'] ==
            'com.example.globe_news_beta',
      );
      const options = DefaultFirebaseOptions.android;
      expect(options.projectId, project['project_id']);
      expect(options.messagingSenderId, project['project_number'].toString());
      expect(options.appId, client['client_info']['mobilesdk_app_id']);
      expect(options.apiKey, client['api_key'][0]['current_key']);
      expect(options.storageBucket, project['storage_bucket']);
    },
    skip: services.existsSync() ? false : 'Local google-services.json required',
  );

  test('FlutterFire metadata matches the Dart Firebase options', () {
    final config = jsonDecode(File('firebase.json').readAsStringSync());
    final platforms = config['flutter']['platforms'];
    final android = platforms['android']['default'];
    final dart = platforms['dart']['lib/firebase_options.dart'];
    const options = DefaultFirebaseOptions.android;
    expect(android['projectId'], options.projectId);
    expect(android['appId'], options.appId);
    expect(dart['projectId'], options.projectId);
    expect(dart['configurations']['android'], options.appId);
  });
}
