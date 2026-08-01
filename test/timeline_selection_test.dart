import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/timeline/timeline_selection.dart';

void main() {
  test('selects the latest completed 15-minute IST slot', () {
    final selection = TimelineSelection.latestCompleted(
      utcNow: DateTime.utc(2026, 7, 31, 10, 47),
    );

    expect(selection.ist, DateTime.utc(2026, 7, 31, 16, 15));
  });

  test('converts selected IST date and time to UTC for the API', () {
    final selection = TimelineSelection(DateTime.utc(2026, 7, 31, 0, 15));

    expect(selection.utc, DateTime.utc(2026, 7, 30, 18, 45));
    expect(selection.apiDate, '2026-07-30');
    expect(selection.apiTime, '18:45');
  });
}
