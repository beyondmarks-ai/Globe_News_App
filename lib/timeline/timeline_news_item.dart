class TimelineNewsItem {
  const TimelineNewsItem({
    required this.id,
    required this.place,
    required this.country,
    required this.lat,
    required this.lon,
    required this.tone,
    required this.color,
    required this.url,
    required this.source,
    required this.hasEmbedding,
    required this.aiReady,
    required this.pulseStrength,
    this.headline = '',
  });

  static const minPulseStrength = 0.5;
  static const maxPulseStrength = 2.0;

  final String id;
  final String place;
  final String country;
  final double lat;
  final double lon;
  final double tone;
  final String color;
  final String url;
  final String source;
  final bool hasEmbedding;
  final bool aiReady;
  final double pulseStrength;
  final String headline;

  bool get pulseReady => hasEmbedding && aiReady;

  static TimelineNewsItem? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final lat = _asDouble(json['lat'] ?? json['latitude']);
    final lon = _asDouble(json['lon'] ?? json['lng'] ?? json['longitude']);
    if (lat == null ||
        lon == null ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      return null;
    }

    final rawId = json['id']?.toString().trim();
    if (rawId == null || rawId.isEmpty) return null;
    final tone = _asDouble(json['tone']) ?? 0;
    final strength =
        (_asDouble(json['pulse_strength'] ?? json['pulseStrength']) ?? 1)
            .clamp(minPulseStrength, maxPulseStrength)
            .toDouble();

    return TimelineNewsItem(
      id: rawId,
      place: _asText(json['place']),
      country: _asText(json['country']),
      lat: lat,
      lon: lon,
      tone: tone,
      color: _normalizeColor(json['color'], tone),
      url: _asText(json['url']),
      source: _asText(json['source']),
      hasEmbedding: _asBool(json['has_embedding'] ?? json['hasEmbedding']),
      aiReady: _asBool(json['ai_ready'] ?? json['aiReady']),
      pulseStrength: strength,
      headline: _asText(
        json['headline'] ??
            json['title'] ??
            json['headlineEnglish'] ??
            json['headlineKannada'],
      ),
    );
  }

  static String _asText(Object? value) => value?.toString().trim() ?? '';

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    switch (value?.toString().trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
      default:
        return false;
    }
  }

  static String _normalizeColor(Object? value, double tone) {
    final color = value?.toString().trim().toLowerCase();
    if (color == 'red' || color == 'yellow' || color == 'green') return color!;
    if (value != null && color != null && color.isNotEmpty) return 'unknown';
    if (tone < 0) return 'red';
    if (tone > 0) return 'green';
    return 'yellow';
  }
}
