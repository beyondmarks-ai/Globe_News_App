import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:globe_news_beta/notifications/alert_messaging.dart';
import 'package:globe_news_beta/notifications/news_alert.dart';
import 'package:globe_news_beta/notifications/news_alert_api.dart';
import 'package:globe_news_beta/notifications/news_alert_controller.dart';

class TestMessaging implements AlertMessaging {
  bool permission = true;
  final changes = StreamController<String>.broadcast();
  @override
  Future<bool> allowed({required bool request}) async => permission;
  @override
  Future<String?> token() async => 'test-fcm-token-for-device';
  @override
  Stream<String> get tokenChanges => changes.stream;
}

class TestAlertApi extends NewsAlertApi {
  TestAlertApi() : super(baseUrl: 'https://example.com');
  final saved = <NewsAlert>[];
  int disabled = 0;
  bool failSave = false;
  bool failDisable = false;
  @override
  Future<void> save({
    required NewsAlert alert,
    required String installationId,
    required String deviceSecret,
    required String fcmToken,
  }) async {
    if (failSave) throw const NewsAlertApiException('Service unavailable');
    saved.add(alert);
  }

  @override
  Future<void> disable({
    required String installationId,
    required String deviceSecret,
  }) async {
    if (failDisable) throw const NewsAlertApiException('Service unavailable');
    disabled++;
  }
}

const area = NewsAlert(
  latitude: 12.97,
  longitude: 77.59,
  locationLabel: 'Bengaluru, Karnataka, India',
  locationType: 'place',
  scope: NewsAlertScope.customRadius,
  radiusMeters: 10000,
  language: 'en-US',
  mode: NewsAlertMode.smart,
  quietHoursEnabled: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  NewsAlertController create(
    String user,
    TestAlertApi api,
    TestMessaging messaging,
  ) {
    final controller = NewsAlertController(
      api: api,
      userId: user,
      messaging: messaging,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('area preferences belong to the signed-in account', () async {
    final messaging = TestMessaging();
    addTearDown(messaging.changes.close);
    final a = create('a', TestAlertApi(), messaging);
    await a.load();
    await a.saveWithoutNotifications(area);
    final b = create('b', TestAlertApi(), messaging);
    await b.load();
    expect(b.alert, isNull);
    final restored = create('a', TestAlertApi(), messaging);
    await restored.load();
    expect(restored.alert?.radiusMeters, 10000);
    expect(restored.notificationsEnabled, isFalse);
  });
  test('permission denial does not pretend alerts are enabled', () async {
    final api = TestAlertApi();
    final messaging = TestMessaging()..permission = false;
    addTearDown(messaging.changes.close);
    final controller = create('a', api, messaging);
    await controller.load();
    expect(await controller.save(area), isFalse);
    expect(api.saved, isEmpty);
    expect(controller.notificationsEnabled, isFalse);
    expect(await controller.saveWithoutNotifications(area), isTrue);
    expect(controller.alert?.enabled, isFalse);
  });
  test('failed backend registration leaves no enabled preference', () async {
    final api = TestAlertApi()..failSave = true;
    final messaging = TestMessaging();
    addTearDown(messaging.changes.close);
    final controller = create('a', api, messaging);
    await controller.load();
    expect(await controller.save(area), isFalse);
    expect(controller.alert, isNull);
    expect(controller.error, 'Service unavailable');
  });
  test(
    'sign out unregisters delivery but preserves area for next sign in',
    () async {
      final api = TestAlertApi();
      final messaging = TestMessaging();
      addTearDown(messaging.changes.close);
      final controller = create('a', api, messaging);
      await controller.load();
      expect(await controller.save(area), isTrue);
      expect(api.saved.single.radiusMeters, 10000);
      expect(await controller.suspendForSignOut(), isTrue);
      messaging.changes.add('new-token');
      await Future<void>.delayed(Duration.zero);
      expect(api.saved.length, 1);
      expect(api.disabled, 1);
      final nextApi = TestAlertApi();
      final restored = create('a', nextApi, messaging);
      await restored.load();
      await Future<void>.delayed(Duration.zero);
      expect(restored.alert?.locationLabel, area.locationLabel);
      expect(restored.notificationsEnabled, isTrue);
      expect(nextApi.saved.length, 1);
    },
  );
  test(
    'failed unregister blocks sign out instead of leaving private alerts active',
    () async {
      final api = TestAlertApi();
      final messaging = TestMessaging();
      addTearDown(messaging.changes.close);
      final controller = create('a', api, messaging);
      await controller.load();
      await controller.save(area);
      api.failDisable = true;
      expect(await controller.suspendForSignOut(), isFalse);
      expect(controller.error, contains('sign out again'));
    },
  );
}
