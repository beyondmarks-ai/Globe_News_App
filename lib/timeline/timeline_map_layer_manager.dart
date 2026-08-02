import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'timeline_geojson.dart';
import 'timeline_news_item.dart';

class TimelineMapLayerManager {
  TimelineMapLayerManager({required this.onItemTapped});

  static const sourceId = 'timeline-news';
  static const dotLayerId = 'timeline-news-dots';
  static const _dotTapInteractionId = 'timeline-news-dot-tap';

  final ValueChanged<TimelineNewsItem> onItemTapped;
  MapboxMap? _map;
  List<TimelineNewsItem> _items = const [];
  Map<String, TimelineNewsItem> _itemsById = const {};
  bool _styleReady = false;
  bool _disposed = false;

  void attach(MapboxMap map) {
    if (_disposed) return;
    _map = map;
  }

  Future<void> onStyleLoaded() async {
    final map = _map;
    if (_disposed || map == null) return;
    _styleReady = false;
    await _ensureSourceAndLayers(map);
    if (_disposed || !identical(map, _map)) return;
    _registerTapInteractions(map);
    _styleReady = true;
  }

  Future<void> setItems(List<TimelineNewsItem> items) async {
    if (_disposed) return;
    _items = List.unmodifiable(items);
    _itemsById = {for (final item in items) item.id: item};
    final map = _map;
    if (map != null && _styleReady) {
      try {
        await _updateSource(map);
      } catch (_) {
        // A concurrent style change will restore the source on style-loaded.
      }
    }
  }

  Future<void> _ensureSourceAndLayers(MapboxMap map) async {
    final style = map.style;
    if (!await style.styleSourceExists(sourceId)) {
      await style.addSource(
        GeoJsonSource(
          id: sourceId,
          data: TimelineGeoJson.featureCollection(_items),
        ),
      );
    } else {
      await _updateSource(map);
    }

    if (!await style.styleLayerExists(dotLayerId)) {
      await style.addLayer(
        CircleLayer(
          id: dotLayerId,
          sourceId: sourceId,
          circleColorExpression: _dotColorExpression,
          circleOpacity: 0.82,
          circleRadiusExpression: _dotRadiusExpression,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeOpacity: 0.78,
          circleStrokeWidth: 1.15,
          circleEmissiveStrength: 0.8,
        ),
      );
    }
  }

  Future<void> _updateSource(MapboxMap map) async {
    final source = await map.style.getSource(sourceId);
    if (source is GeoJsonSource) {
      await source.updateGeoJSON(TimelineGeoJson.featureCollection(_items));
    }
  }

  void _registerTapInteractions(MapboxMap map) {
    map.removeInteraction(_dotTapInteractionId);
    map.addInteraction(
      TapInteraction(
        FeaturesetDescriptor(layerId: dotLayerId),
        radius: 22,
        (feature, _) => _handleFeatureTap(feature),
      ),
      interactionID: _dotTapInteractionId,
    );
  }

  void _handleFeatureTap(FeaturesetFeature feature) {
    if (_disposed || !_styleReady || _itemsById.isEmpty) return;
    final id = feature.properties['id']?.toString();
    final item = id == null ? null : _itemsById[id];
    if (item != null) onItemTapped(item);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final map = _map;
    _map = null;
    if (map != null) {
      map.removeInteraction(_dotTapInteractionId);
    }
  }

  static final List<Object> _dotColorExpression = <Object>[
    'match',
    <Object>['get', 'color'],
    'red',
    '#ff4d5e',
    'green',
    '#00e88a',
    'yellow',
    '#f6d44a',
    '#67a8ff',
  ];

  static final List<Object> _dotRadiusExpression = <Object>[
    'interpolate',
    <Object>['linear'],
    <Object>['zoom'],
    1,
    4,
    4,
    7,
    8,
    14,
  ];
}
