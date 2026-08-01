import 'dart:convert';

/// Basemap definitions used by the native Mapbox renderer.
abstract final class GlobeMapStyles {
  static const darkStyleUri =
      'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';

  static const _cartoVectorTileJson =
      'https://tiles.basemaps.cartocdn.com/vector/carto.streets/v1/tiles.json';

  static const _esriTileTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}';

  static const _esriAttribution =
      'Esri, Maxar, Earthstar Geographics, and the GIS User Community';

  /// Esri does not publish this service as a Mapbox style document. This
  /// equivalent Style Specification v8 document lets Mapbox's native renderer
  /// drape the imagery over its globe. CARTO's boundary source supplies the
  /// requested administrative lines in satellite mode.
  static String get satelliteStyleJson => jsonEncode({
    'version': 8,
    'name': 'Esri World Imagery Globe',
    'projection': {'name': 'globe'},
    'sources': {
      'esri-world-imagery': {
        'type': 'raster',
        'tiles': [_esriTileTemplate],
        'tileSize': 256,
        'maxzoom': 19,
        'attribution': _esriAttribution,
      },
      'carto-boundaries': {'type': 'vector', 'url': _cartoVectorTileJson},
    },
    'layers': [
      {
        'id': 'space-background',
        'type': 'background',
        'paint': {'background-color': '#030712'},
      },
      {
        'id': 'esri-world-imagery',
        'type': 'raster',
        'source': 'esri-world-imagery',
        'paint': {'raster-opacity': 1, 'raster-resampling': 'linear'},
      },
      {
        'id': 'boundary_state',
        'type': 'line',
        'source': 'carto-boundaries',
        'source-layer': 'boundary',
        'minzoom': 0,
        'filter': [
          'all',
          ['==', 'admin_level', 4],
          ['==', 'maritime', 0],
        ],
        'paint': {
          'line-color': '#4B5563',
          'line-opacity': 0.72,
          'line-width': 0.75,
        },
      },
      {
        'id': 'boundary_country',
        'type': 'line',
        'source': 'carto-boundaries',
        'source-layer': 'boundary',
        'minzoom': 0,
        'filter': [
          'all',
          ['==', 'admin_level', 2],
          ['==', 'maritime', 0],
        ],
        'paint': {
          'line-color': '#6B7280',
          'line-opacity': 0.88,
          'line-width': 1.1,
        },
      },
    ],
  });
}
