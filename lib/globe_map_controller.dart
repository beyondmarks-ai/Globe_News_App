import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_basemap.dart';
import 'map_styles.dart';
import 'place_search/place_search_result.dart';

/// Owns globe behavior and runtime styling. The [MapWidget] retains ownership
/// of the native map resource and disposes it when it leaves the widget tree.
class GlobeMapController extends ChangeNotifier {
  static const _resumeDelay = Duration(seconds: 3);
  static const _rotationInterval = Duration(milliseconds: 33);
  static const _degreesPerSecond = 6.0;
  static const _atmosphereLayerId = 'globe-atmosphere';

  MapboxMap? _map;
  Timer? _resumeTimer;
  Timer? _rotationTimer;
  MapBasemap _basemap = MapBasemap.dark;
  bool _appIsActive = true;
  bool _styleIsReady = false;
  bool _userIsInteracting = false;
  bool _rotationSuspended = false;
  bool _cameraUpdateInFlight = false;
  bool _disposed = false;
  bool _isChangingBasemap = false;
  String? _lastError;
  CameraState? _latestCamera;
  Stopwatch? _rotationClock;
  Duration _lastRotationTick = Duration.zero;

  MapBasemap get basemap => _basemap;
  bool get isChangingBasemap => _isChangingBasemap;
  String? get lastError => _lastError;
  bool get isRotationSuspended => _rotationSuspended;

  void attach(MapboxMap map) {
    if (_disposed) return;
    _map = map;
    unawaited(_configureMap(map));
  }

  Future<void> _configureMap(MapboxMap map) async {
    try {
      await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
      await map.logo.updateSettings(
        LogoSettings(
          position: OrnamentPosition.BOTTOM_RIGHT,
          marginRight: 12,
          marginBottom: 90,
        ),
      );
      await map.attribution.updateSettings(
        AttributionSettings(
          position: OrnamentPosition.BOTTOM_RIGHT,
          marginRight: 12,
          marginBottom: 64,
          iconColor: const Color(0xFF7D8CA8).toARGB32(),
          clickable: true,
        ),
      );
    } catch (_) {
      // Ornament setup must not prevent the map from loading.
    }
    try {
      final camera = await map.getCameraState();
      if (!_disposed && identical(map, _map)) _latestCamera = camera;
    } catch (_) {
      // The first camera-change event will populate the state instead.
    }
  }

  void onCameraChanged(CameraState camera) {
    if (_disposed) return;
    _latestCamera = camera;
  }

  Future<void> onStyleLoaded() async {
    final map = _map;
    if (_disposed || map == null) return;

    _styleIsReady = false;
    try {
      await map.style.setProjection(
        StyleProjection(name: StyleProjectionName.globe),
      );
      if (_disposed || !identical(map, _map)) return;

      await _applyAtmosphere(map);
      await _styleAdministrativeBorders(map);
      if (_disposed || !identical(map, _map)) return;

      _styleIsReady = true;
      _isChangingBasemap = false;
      _lastError = null;
      _startRotationIfAllowed();
      notifyListeners();
    } catch (error) {
      if (_disposed || !identical(map, _map)) return;
      _isChangingBasemap = false;
      _lastError = 'The map style could not be configured: $error';
      notifyListeners();
    }
  }

  Future<void> setBasemap(MapBasemap next) async {
    final map = _map;
    if (_disposed || map == null || next == _basemap || _isChangingBasemap) {
      return;
    }

    _basemap = next;
    _isChangingBasemap = true;
    _styleIsReady = false;
    _lastError = null;
    _stopRotation();
    notifyListeners();

    try {
      if (next == MapBasemap.dark) {
        await map.loadStyleURI(GlobeMapStyles.darkStyleUri);
      } else {
        await map.loadStyleJson(GlobeMapStyles.satelliteStyleJson);
      }
    } catch (error) {
      if (_disposed || !identical(map, _map)) return;
      _isChangingBasemap = false;
      _lastError = 'The basemap could not be loaded: $error';
      notifyListeners();
    }
  }

  void onInteractionStart() {
    if (_disposed) return;
    _userIsInteracting = true;
    _pauseForUserActivity();
  }

  void onInteractionEnd() {
    if (_disposed) return;
    _userIsInteracting = false;
    _scheduleRotationResume();
  }

  /// Used by native scroll/zoom callbacks, including gestures that do not
  /// produce a Flutter pointer-up event.
  void registerUserActivity() {
    if (_disposed) return;
    if (!_userIsInteracting) _pauseForUserActivity();
    _scheduleRotationResume();
  }

  void setAppActive(bool active) {
    if (_disposed || _appIsActive == active) return;
    _appIsActive = active;
    if (active) {
      _scheduleRotationResume();
    } else {
      _resumeTimer?.cancel();
      _stopRotation();
    }
  }

  void setRotationSuspended(bool suspended) {
    if (_disposed || _rotationSuspended == suspended) return;
    _rotationSuspended = suspended;
    _resumeTimer?.cancel();
    if (suspended) {
      _stopRotation();
      final map = _map;
      if (map != null) unawaited(map.cancelCameraAnimation());
    } else {
      _scheduleRotationResume();
    }
    notifyListeners();
  }

  Future<void> flyToPlace(PlaceSearchResult place) async {
    final map = _map;
    if (_disposed || map == null || !_styleIsReady) return;

    _resumeTimer?.cancel();
    _stopRotation();
    _lastError = null;
    notifyListeners();
    try {
      await map.cancelCameraAnimation();
      if (_disposed || !identical(map, _map)) return;
      await map.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(place.longitude, place.latitude)),
          zoom: place.preferredZoom,
          pitch: 0,
        ),
        MapAnimationOptions(duration: 2200, startDelay: 0),
      );
    } catch (error) {
      if (_disposed || !identical(map, _map)) return;
      _lastError = 'Could not move to ${place.name}.';
      notifyListeners();
    } finally {
      if (!_disposed && identical(map, _map)) _scheduleRotationResume();
    }
  }

  void clearError() {
    if (_disposed || _lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> _applyAtmosphere(MapboxMap map) async {
    if (await map.style.styleLayerExists(_atmosphereLayerId)) return;

    await map.style.addLayer(
      SkyLayer(
        id: _atmosphereLayerId,
        skyType: SkyType.ATMOSPHERE,
        skyAtmosphereColor: const Color(0x6618273F).toARGB32(),
        skyAtmosphereHaloColor: const Color(0xB377A7D9).toARGB32(),
        skyAtmosphereSunIntensity: 1.5,
        skyOpacity: 1,
      ),
    );
  }

  Future<void> _styleAdministrativeBorders(MapboxMap map) async {
    final layers = await map.style.getStyleLayers();

    for (final layer in layers) {
      if (layer == null || layer.type != 'line') continue;
      final id = layer.id.toLowerCase();

      if (_isCountryBorder(id)) {
        await _setLineStyle(
          map,
          layer.id,
          color: '#6B7280',
          opacity: 0.88,
          width: 1.1,
        );
      } else if (_isStateBorder(id)) {
        await _setLineStyle(
          map,
          layer.id,
          color: '#4B5563',
          opacity: 0.72,
          width: 0.75,
        );
      }
    }
  }

  bool _isCountryBorder(String id) =>
      id.contains('boundary_country') ||
      id.contains('country_boundary') ||
      id.contains('admin-0') ||
      id.contains('admin_0');

  bool _isStateBorder(String id) =>
      id.contains('boundary_state') ||
      id.contains('state_boundary') ||
      id.contains('province_boundary') ||
      id.contains('admin-1') ||
      id.contains('admin_1');

  Future<void> _setLineStyle(
    MapboxMap map,
    String layerId, {
    required String color,
    required double opacity,
    required double width,
  }) async {
    await map.style.setStyleLayerProperty(layerId, 'line-color', color);
    await map.style.setStyleLayerProperty(layerId, 'line-opacity', opacity);
    await map.style.setStyleLayerProperty(layerId, 'line-width', width);
  }

  void _pauseForUserActivity() {
    _resumeTimer?.cancel();
    _stopRotation();
    final map = _map;
    if (map != null) unawaited(map.cancelCameraAnimation());
  }

  void _scheduleRotationResume() {
    _resumeTimer?.cancel();
    if (!_appIsActive || !_styleIsReady || _rotationSuspended) return;
    _resumeTimer = Timer(_resumeDelay, _startRotationIfAllowed);
  }

  void _startRotationIfAllowed() {
    if (_disposed ||
        !_appIsActive ||
        !_styleIsReady ||
        _rotationSuspended ||
        _userIsInteracting ||
        _map == null ||
        _rotationTimer?.isActive == true) {
      return;
    }

    _rotationClock = Stopwatch()..start();
    _lastRotationTick = Duration.zero;
    unawaited(_map!.setUserAnimationInProgress(true));
    _rotationTimer = Timer.periodic(_rotationInterval, (_) {
      unawaited(_rotateOneFrame());
    });
  }

  Future<void> _rotateOneFrame() async {
    final map = _map;
    final camera = _latestCamera;
    final clock = _rotationClock;
    if (_disposed ||
        map == null ||
        camera == null ||
        clock == null ||
        !_appIsActive ||
        !_styleIsReady ||
        _rotationSuspended ||
        _userIsInteracting ||
        _cameraUpdateInFlight) {
      return;
    }

    final now = clock.elapsed;
    final elapsedSeconds = ((now - _lastRotationTick).inMicroseconds / 1000000)
        .clamp(0.0, 0.1);
    _lastRotationTick = now;
    if (elapsedSeconds == 0) return;

    _cameraUpdateInFlight = true;
    try {
      if (_disposed || !identical(map, _map) || _userIsInteracting) return;
      final longitude = camera.center.coordinates.lng.toDouble();
      final nextLongitude =
          ((longitude + (_degreesPerSecond * elapsedSeconds) + 180) % 360) -
          180;

      await map.setCamera(
        CameraOptions(
          center: Point(
            coordinates: Position(nextLongitude, camera.center.coordinates.lat),
          ),
        ),
      );
    } catch (_) {
      // A style change or gesture can invalidate an in-flight camera update.
    } finally {
      _cameraUpdateInFlight = false;
    }
  }

  void _stopRotation() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _rotationClock?.stop();
    _rotationClock = null;
    final map = _map;
    if (map != null) unawaited(map.setUserAnimationInProgress(false));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _resumeTimer?.cancel();
    _stopRotation();
    final map = _map;
    _map = null;
    if (map != null) unawaited(map.cancelCameraAnimation());
    super.dispose();
  }
}
