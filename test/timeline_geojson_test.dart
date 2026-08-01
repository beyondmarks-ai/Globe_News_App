import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/timeline/timeline_geojson.dart';
import 'package:globe_news_beta/timeline/timeline_news_item.dart';

void main() {
  test('writes longitude before latitude and calculates pulseReady', () {
    const item = TimelineNewsItem(
      id: 'news-id',
      place: 'Bidar',
      country: 'India',
      lat: 17.9104,
      lon: 77.5199,
      tone: -3.2,
      color: 'red',
      url: 'https://example.com',
      source: 'Source',
      hasEmbedding: true,
      aiReady: true,
      pulseStrength: 1.2,
    );

    final feature = TimelineGeoJson.feature(item);
    final geometry = feature['geometry']! as Map<String, Object?>;
    final properties = feature['properties']! as Map<String, Object?>;

    expect(geometry['coordinates'], [77.5199, 17.9104]);
    expect(properties['pulseReady'], 1);
    expect(properties['pulseStrength'], 1.2);
  });
}
