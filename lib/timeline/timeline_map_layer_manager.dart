import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'timeline_geojson.dart';
import 'timeline_news_item.dart';

class TimelineMapLayerManager {
  TimelineMapLayerManager({required this.onItemTapped});

  static const sourceId = 'timeline-news';
  static const pulseLayerId = 'timeline-news-embedding-pulses';
  static const dotLayerId = 'timeline-news-dots';
  static const highlightLayerId = 'timeline-news-ai-ready-dots';
  static const _dotTapInteractionId = 'timeline-news-dot-tap';
  static const _highlightTapInteractionId = 'timeline-news-highlight-tap';

  final ValueChanged<TimelineNewsItem> onItemTapped;
  MapboxMap? _map;
  List<TimelineNewsItem> _items = const [];
  Map<String, TimelineNewsItem> _itemsById = const {};
  Timer? _pulseTimer;
  Stopwatch? _pulseClock;
  bool _styleReady = false;
  bool _appActive = true;
  bool _pulseUpdateInFlight = false;
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
    _startPulseIfNeeded();
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
    _startPulseIfNeeded();
  }

  void setAppActive(bool active) {
    if (_disposed || _appActive == active) return;
    _appActive = active;
    if (active) {
      _startPulseIfNeeded();
    } else {
      _stopPulse();
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

    if (!await style.styleLayerExists(pulseLayerId)) {
      await style.addLayer(
        CircleLayer(
          id: pulseLayerId,
          sourceId: sourceId,
          filter: _pulseFilter,
          circleColorExpression: _dotColorExpression,
          circleOpacity: 0.28,
          circleRadius: 14,
          circleStrokeColorExpression: _dotColorExpression,
          circleStrokeOpacity: 0.72,
          circleStrokeWidth: 1.5,
          circleBlur: 0.2,
          circleEmissiveStrength: 1,
        ),
      );
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
    if (!await style.styleLayerExists(highlightLayerId)) {
      await style.addLayer(
        CircleLayer(
          id: highlightLayerId,
          sourceId: sourceId,
          filter: _pulseFilter,
          circleColorExpression: _dotColorExpression,
          circleOpacity: 0.2,
          circleRadiusExpression: _highlightRadiusExpression,
          circleStrokeColorExpression: _highlightColorExpression,
          circleStrokeOpacity: 0.95,
          circleStrokeWidth: 2,
          circleEmissiveStrength: 1,
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

  void _startPulseIfNeeded() {
    if (_disposed ||
        !_appActive ||
        !_styleReady ||
        !_items.any((item) => item.pulseReady)) {
      _stopPulse();
      return;
    }
    if (_pulseTimer?.isActive == true) return;
    _pulseClock = Stopwatch()..start();
    _pulseTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => unawaited(_updatePulse()),
    );
  }

  Future<void> _updatePulse() async {
    final map = _map;
    final clock = _pulseClock;
    if (_disposed ||
        map == null ||
        clock == null ||
        !_styleReady ||
        _pulseUpdateInFlight) {
      return;
    }
    final phase = (clock.elapsedMilliseconds % 1800) / 1800;
    final opacity = math.pow(1 - phase, 1.4).toDouble();
    _pulseUpdateInFlight = true;
    try {
      await map.style.setStyleLayerProperty(
        pulseLayerId,
        'circle-radius',
        _pulseRadiusExpression(phase),
      );
      await map.style.setStyleLayerProperty(
        pulseLayerId,
        'circle-opacity',
        0.24 * opacity,
      );
      await map.style.setStyleLayerProperty(
        pulseLayerId,
        'circle-stroke-opacity',
        0.78 * opacity,
      );
    } catch (_) {
      // Style replacement temporarily removes the pulse layer.
    } finally {
      _pulseUpdateInFlight = false;
    }
  }

  void _registerTapInteractions(MapboxMap map) {
    map.removeInteraction(_dotTapInteractionId);
    map.removeInteraction(_highlightTapInteractionId);
    map.addInteraction(
      TapInteraction(
        FeaturesetDescriptor(layerId: dotLayerId),
        radius: 22,
        (feature, _) => _handleFeatureTap(feature),
      ),
      interactionID: _dotTapInteractionId,
    );
    map.addInteraction(
      TapInteraction(
        FeaturesetDescriptor(layerId: highlightLayerId),
        radius: 22,
        (feature, _) => _handleFeatureTap(feature),
      ),
      interactionID: _highlightTapInteractionId,
    );
  }

  void _handleFeatureTap(FeaturesetFeature feature) {
    if (_disposed || !_styleReady || _itemsById.isEmpty) return;
    final id = feature.properties['id']?.toString();
    final item = id == null ? null : _itemsById[id];
    if (item != null) onItemTapped(item);
  }

  void _stopPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _pulseClock?.stop();
    _pulseClock = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopPulse();
    final map = _map;
    _map = null;
    if (map != null) {
      map.removeInteraction(_dotTapInteractionId);
      map.removeInteraction(_highlightTapInteractionId);
    }
  }

  static final List<Object> _pulseFilter = <Object>[
    '==',
    <Object>['get', 'pulseReady'],
    1,
  ];

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

  static final List<Object> _highlightColorExpression = <Object>[
    'match',
    <Object>['get', 'color'],
    'red',
    '#ffd2d7',
    'green',
    '#ccffe8',
    'yellow',
    '#fff3b8',
    '#d9e8ff',
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

  static final List<Object> _highlightRadiusExpression = <Object>[
    'interpolate',
    <Object>['linear'],
    <Object>['zoom'],
    1,
    6.2,
    4,
    9.2,
    8,
    16.2,
  ];

  static List<Object> _pulseRadiusExpression(double phase) => <Object>[
    'interpolate',
    <Object>['linear'],
    <Object>['zoom'],
    1,
    <Object>[
      '*',
      <Object>['get', 'pulseStrength'],
      8 + (phase * 22),
    ],
    4,
    <Object>[
      '*',
      <Object>['get', 'pulseStrength'],
      12 + (phase * 34),
    ],
    8,
    <Object>[
      '*',
      <Object>['get', 'pulseStrength'],
      20 + (phase * 52),
    ],
  ];
}
