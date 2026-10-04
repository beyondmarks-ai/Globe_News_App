import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:globe_news_beta/timeline/timeline_news_api.dart';
import 'package:globe_news_beta/timeline/timeline_selection.dart';

void main() {
  test('flattens records nested in timeline slot data arrays', () {
    final records = timelineRecordsFromResponse([
      {
        'timestamp': '20260731123000',
        'data': [
          {'id': 'one'},
          {'id': 'two'},
        ],
      },
      {
        'timestamp': '20260731121500',
        'data': [
          {'id': 'three'},
        ],
      },
    ]).toList();
    expect(records.map((record) => (record as Map)['id']), [
      'one',
      'two',
      'three',
    ]);
  });
  test('preserves an already-flat response', () {
    final records = timelineRecordsFromResponse([
      {'id': 'one'},
      {'id': 'two'},
    ]).toList();
    expect(records, hasLength(2));
  });
  test(
    'slow optional city source cannot hold timeline for twenty seconds',
    () async {
      final pending = Completer<http.Response>();
      final api = TimelineNewsApi(
        baseUrl: 'https://example.com',
        clientFactory: () => MockClient((request) async {
          if (request.url.path.contains('city-news')) return pending.future;
          return http.Response(
            jsonEncode([
              {
                'id': 'a',
                'headline': 'Source story',
                'lat': 12.9,
                'lon': 77.5,
                'tone': 0,
                'place': 'Bengaluru',
                'country': 'India',
                'url': 'https://example.com/story',
                'source': 'Example',
              },
            ]),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final result = await api
          .fetch(TimelineSelection.latestCompleted())
          .timeout(const Duration(seconds: 5));
      expect(result.single.headline, 'Source story');
      pending.complete(http.Response('{}', 200));
    },
  );
}
