import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/notifications/news_alert.dart';

void main() {
  test('news alert preserves GeoJSON longitude latitude order', () {
    const alert = NewsAlert(
      latitude: 17.9133,
      longitude: 77.5301,
      locationLabel: 'Bidar',
      locationType: 'place',
      scope: NewsAlertScope.customRadius,
      radiusMeters: 10000,
      language: 'kn-IN',
      mode: NewsAlertMode.smart,
      quietHoursEnabled: true,
    );

    final center = alert.toJson()['center']! as Map<String, Object?>;
    expect(center['coordinates'], [77.5301, 17.9133]);
    expect(NewsAlert.tryParse(alert.toJson())?.locationLabel, 'Bidar');
  });

  test('news alert rejects unsupported radius and invalid coordinates', () {
    final valid = <String, Object?>{
      'center': {
        'type': 'Point',
        'coordinates': [77.5301, 17.9133],
      },
      'locationLabel': 'Bidar',
      'radiusMeters': 10000,
      'language': 'en-US',
      'mode': 'smart',
      'quietHours': {'enabled': true},
    };
    expect(NewsAlert.tryParse({...valid, 'radiusMeters': 9000}), isNull);
    expect(
      NewsAlert.tryParse({
        ...valid,
        'center': {
          'type': 'Point',
          'coordinates': [181, 17.9133],
        },
      }),
      isNull,
    );
  });

  test('administrative bounds are serialized and restored', () {
    const alert = NewsAlert(
      latitude: 12.979101,
      longitude: 77.591301,
      locationLabel: 'Bengaluru',
      locationType: 'place',
      scope: NewsAlertScope.administrativeBounds,
      boundingBox: [77.325376, 12.733355, 77.783794, 13.234974],
      radiusMeters: 25000,
      language: 'en-US',
      mode: NewsAlertMode.smart,
      quietHoursEnabled: true,
    );

    final parsed = NewsAlert.tryParse(alert.toJson());

    expect(parsed?.scope, NewsAlertScope.administrativeBounds);
    expect(parsed?.boundingBox, alert.boundingBox);
  });
  test('unsupported language safely falls back to English', () {
    final parsed = NewsAlert.tryParse({
      'center': {
        'type': 'Point',
        'coordinates': [77.5301, 17.9133],
      },
      'locationLabel': 'Bidar',
      'radiusMeters': 5000,
      'language': 'xx-XX',
      'mode': 'unknown',
      'quietHours': {'enabled': false},
    });

    expect(parsed?.language, 'en-US');
    expect(parsed?.mode, NewsAlertMode.smart);
  });
}
