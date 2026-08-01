class PlaceSearchResult {
  const PlaceSearchResult({
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.featureType,
  });

  final String name;
  final double longitude;
  final double latitude;
  final String featureType;

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

    final name =
        (properties['full_address'] ??
                properties['name_preferred'] ??
                properties['name'])
            ?.toString()
            .trim();
    if (name == null || name.isEmpty) return null;

    return PlaceSearchResult(
      name: name,
      longitude: lon,
      latitude: lat,
      featureType: properties['feature_type']?.toString() ?? '',
    );
  }
}
