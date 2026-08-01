import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/main.dart';

void main() {
  testWidgets('explains how to configure a missing Mapbox token', (
    tester,
  ) async {
    await tester.pumpWidget(const GlobeNewsApp());

    expect(find.text('Mapbox access token required'), findsOneWidget);
    expect(
      find.textContaining('--dart-define=MAPBOX_ACCESS_TOKEN=YOUR_TOKEN'),
      findsOneWidget,
    );
  });
}
