import 'dart:convert';

import 'timeline_news_item.dart';

abstract final class TimelineGeoJson {
  static String featureCollection(Iterable<TimelineNewsItem> items) =>
      jsonEncode({
        'type': 'FeatureCollection',
        'features': items.map(feature).toList(growable: false),
      });

  static Map<String, Object?> feature(TimelineNewsItem item) => {
    'type': 'Feature',
    'id': item.id,
    'geometry': {
      'type': 'Point',
      'coordinates': [item.lon, item.lat],
    },
    'properties': {
      'id': item.id,
      'place': item.place,
      'country': item.country,
      'tone': item.tone,
      'color': item.color,
      'url': item.url,
      'source': item.source,
      'hasEmbedding': item.hasEmbedding,
      'aiReady': item.aiReady,
      'pulseReady': item.pulseReady ? 1 : 0,
      'pulseStrength': item.pulseStrength,
    },
  };
}
