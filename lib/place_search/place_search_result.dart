class PlaceSearchResult {
  const PlaceSearchResult({
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.featureType,
    this.description = '',
    this.boundingBox,
  });

  final String name;
  final String description;
  final double longitude;
  final double latitude;
  final String featureType;

  /// Mapbox order: min longitude, min latitude, max longitude, max latitude.
  final List<double>? boundingBox;

  bool get hasAdministrativeBounds => boundingBox != null;

  double get preferredZoom => switch (featureType) {
    'country' => 3.2,
    'region' => 4.8,
    'district' => 5.8,
    'place' || 'locality' => 7.2,
    'neighborhood' => 10,
    _ => 8,
  };

  static PlaceSearchResult? fromJson(Map<String, dynamic> json) {
    final properties = json['properties'];
    if (properties is! Map<String, dynamic>) return null;

    final coordinates = properties['coordinates'];
    num? longitude;
    num? latitude;
    if (coordinates is Map<String, dynamic>) {
      longitude = coordinates['longitude'] as num?;
      latitude = coordinates['latitude'] as num?;
    }

    final geometry = json['geometry'];
    final geometryCoordinates = geometry is Map<String, dynamic>
        ? geometry['coordinates']
        : null;
    if ((longitude == null || latitude == null) &&
        geometryCoordinates is List &&
        geometryCoordinates.length >= 2) {
      longitude = geometryCoordinates[0] as num?;
      latitude = geometryCoordinates[1] as num?;
    }

    final lon = longitude?.toDouble();
    final lat = latitude?.toDouble();
    if (lon == null ||
        lat == null ||
        !lon.isFinite ||
        !lat.isFinite ||
        lon < -180 ||
        lon > 180 ||
        lat < -90 ||
        lat > 90) {
      return null;
    }

    String clean(Object? value) => value?.toString().trim() ?? '';

    final preferredName = clean(properties['name_preferred']);
    final basicName = clean(properties['name']);
    final fullAddress = clean(properties['full_address']);
    final placeFormatted = clean(properties['place_formatted']);
    final name = preferredName.isNotEmpty
        ? preferredName
        : basicName.isNotEmpty
        ? basicName
        : fullAddress;
    if (name.isEmpty) return null;

    final description = fullAddress.isNotEmpty && fullAddress != name
        ? fullAddress
        : placeFormatted.isNotEmpty && placeFormatted != name
        ? placeFormatted
        : '';

    return PlaceSearchResult(
      name: name,
      description: description,
      longitude: lon,
      latitude: lat,
      featureType: properties['feature_type']?.toString() ?? '',
      boundingBox: _boundingBox(properties['bbox'] ?? json['bbox']),
    );
  }

  static List<double>? _boundingBox(Object? value) {
    if (value is! List || value.length != 4) return null;
    final values = value
        .map((item) => item is num ? item.toDouble() : double.nan)
        .toList(growable: false);
    if (values.any((item) => !item.isFinite) ||
        values[0] < -180 ||
        values[2] > 180 ||
        values[1] < -90 ||
        values[3] > 90 ||
        values[0] >= values[2] ||
        values[1] >= values[3]) {
      return null;
    }
    return List.unmodifiable(values);
  }
}
