import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:globe_news_beta/notifications/news_alert.dart';
import 'package:globe_news_beta/notifications/news_alert_api.dart';

const area = NewsAlert(
  latitude: 12.97,
  longitude: 77.59,
  locationLabel: 'Bengaluru',
  locationType: 'place',
  scope: NewsAlertScope.customRadius,
  radiusMeters: 10000,
  language: 'en-US',
  mode: NewsAlertMode.smart,
  quietHoursEnabled: false,
);

void main() {
  test(
    'HTTP 200 without saved acknowledgment does not enable alerts',
    () async {
      final api = NewsAlertApi(
        baseUrl: 'https://example.com',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(api.dispose);
      await expectLater(
        api.save(
          alert: area,
          installationId: 'device',
          deviceSecret: 'secret',
          fcmToken: 'token',
        ),
        throwsA(isA<NewsAlertApiException>()),
      );
    },
  );
  test(
    'transient unregister failure retries with same device credentials',
    () async {
      var calls = 0;
      final api = NewsAlertApi(
        baseUrl: 'https://example.com',
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.headers['X-Device-Secret'], 'secret');
          return http.Response('{}', ++calls == 1 ? 503 : 200);
        }),
      );
      addTearDown(api.dispose);
      await api.disable(installationId: 'device', deviceSecret: 'secret');
      expect(calls, 2);
    },
  );
  test(
    'test delivery requires FCM acknowledgment and is not automatically retried',
    () async {
      var calls = 0;
      final api = NewsAlertApi(
        baseUrl: 'https://example.com',
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, '/api/news-alerts/test');
          return http.Response('{"accepted":false}', 200);
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        api.sendTest(installationId: 'device', deviceSecret: 'secret'),
        throwsA(isA<NewsAlertApiException>()),
      );
      expect(calls, 1);
    },
  );
}
