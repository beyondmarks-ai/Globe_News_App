import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/timeline/timeline_news_api.dart';

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
}
