enum NewsAlertMode { smart, immediate, digest }

enum NewsAlertScope { administrativeBounds, customRadius }

class NewsAlert {
  const NewsAlert({
    required this.latitude,
    required this.longitude,
    required this.locationLabel,
    required this.locationType,
    required this.scope,
    required this.radiusMeters,
    required this.language,
    required this.mode,
    required this.quietHoursEnabled,
    this.boundingBox,
    this.enabled = true,
  });

  final double latitude;
  final double longitude;
  final String locationLabel;
  final String locationType;
  final NewsAlertScope scope;
  final List<double>? boundingBox;
  final int radiusMeters;
  final String language;
  final NewsAlertMode mode;
  final bool quietHoursEnabled;
  final bool enabled;

  bool get usesCustomRadius => scope == NewsAlertScope.customRadius;

  NewsAlert withEnabled(bool value) => NewsAlert(
    latitude: latitude,
    longitude: longitude,
    locationLabel: locationLabel,
    locationType: locationType,
    scope: scope,
    boundingBox: boundingBox,
    radiusMeters: radiusMeters,
    language: language,
    mode: mode,
    quietHoursEnabled: quietHoursEnabled,
    enabled: value,
  );

  Map<String, Object?> toJson() => {
    'center': {
      'type': 'Point',
      'coordinates': [longitude, latitude],
    },
    'locationLabel': locationLabel,
    'locationType': locationType,
    'scopeType': usesCustomRadius ? 'radius' : 'bounds',
    if (boundingBox != null) 'boundingBox': boundingBox,
    'radiusMeters': radiusMeters,
    'language': language,
    'mode': mode.name,
    'quietHours': {
      'enabled': quietHoursEnabled,
      'start': '22:00',
      'end': '07:00',
    },
    'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    'enabled': enabled,
  };

  static NewsAlert? tryParse(Object? value) {
    if (value is! Map) return null;
    final center = value['center'];
    if (center is! Map || center['coordinates'] is! List) return null;
    final coordinates = center['coordinates'] as List;
    if (coordinates.length < 2) return null;
    final longitude = _number(coordinates[0]);
    final latitude = _number(coordinates[1]);
    final radius = _integer(value['radiusMeters']);
    final bounds = _bounds(value['boundingBox']);
    final requestedScope = value['scopeType'] == 'bounds'
        ? NewsAlertScope.administrativeBounds
        : NewsAlertScope.customRadius;
    if (longitude == null ||
        latitude == null ||
        radius == null ||
        longitude < -180 ||
        longitude > 180 ||
        latitude < -90 ||
        latitude > 90 ||
        !supportedRadii.contains(radius)) {
      return null;
    }
    final quietHours = value['quietHours'];
    return NewsAlert(
      latitude: latitude,
      longitude: longitude,
      locationLabel: value['locationLabel']?.toString().trim() ?? 'Saved area',
      locationType: value['locationType']?.toString().trim() ?? 'place',
      scope:
          requestedScope == NewsAlertScope.administrativeBounds &&
              bounds != null
          ? requestedScope
          : NewsAlertScope.customRadius,
      boundingBox: bounds,
      radiusMeters: radius,
      language: supportedLanguages.containsKey(value['language'])
          ? value['language'].toString()
          : 'en-US',
      mode: NewsAlertMode.values.firstWhere(
        (candidate) => candidate.name == value['mode']?.toString(),
        orElse: () => NewsAlertMode.smart,
      ),
      quietHoursEnabled: quietHours is Map && quietHours['enabled'] == true,
      enabled: value['enabled'] != false,
    );
  }

  static const supportedRadii = <int>[
    2000,
    5000,
    10000,
    25000,
    50000,
    100000,
    250000,
  ];
  static const supportedLanguages = <String, String>{
    'en-US': 'English',
    'kn-IN': 'Kannada',
    'hi-IN': 'Hindi',
    'ur-PK': 'Urdu',
  };

  static List<double>? _bounds(Object? value) {
    if (value is! List || value.length != 4) return null;
    final result = value.map(_number).toList(growable: false);
    if (result.any((item) => item == null)) return null;
    final values = result.cast<double>();
    if (values[0] < -180 ||
        values[2] > 180 ||
        values[1] < -90 ||
        values[3] > 90 ||
        values[0] >= values[2] ||
        values[1] >= values[3]) {
      return null;
    }
    return List.unmodifiable(values);
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static int? _integer(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
}
