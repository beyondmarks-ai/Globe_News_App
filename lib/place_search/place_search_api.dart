import 'dart:convert';

import 'package:http/http.dart' as http;

import 'place_search_result.dart';

abstract interface class PlaceSearchClient {
  Future<PlaceSearchResult?> search(String query);
  void dispose();
}

class PlaceSearchApi implements PlaceSearchClient {
  PlaceSearchApi({
    required this.accessToken,
    this.permanentStorage = false,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String accessToken;
  final bool permanentStorage;
  final http.Client _client;
  bool _disposed = false;

  @override
  Future<PlaceSearchResult?> search(String query) async {
    final results = await searchMany(
      query,
      limit: 1,
      types: 'country,region,district,place,locality,neighborhood',
    );
    return results.firstOrNull;
  }

  Future<List<PlaceSearchResult>> searchMany(
    String query, {
    int limit = 5,
    String types = 'region,district,place,locality',
  }) async {
    final normalized = query.trim();
    if (_disposed) throw StateError('Place search has been disposed.');
    if (accessToken.isEmpty) throw StateError('Mapbox token is missing.');
    if (normalized.isEmpty ||
        normalized.length > 256 ||
        normalized.contains(';')) {
      return const [];
    }

    final parameters = <String, String>{
      'q': normalized,
      'access_token': accessToken,
      'autocomplete': 'false',
      'limit': limit.clamp(1, 10).toString(),
      'types': types,
      'language': 'en',
      'worldview': 'in',
    };
    if (permanentStorage) parameters['permanent'] = 'true';

    final uri = Uri.https(
      'api.mapbox.com',
      '/search/geocode/v6/forward',
      parameters,
    );
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Place search failed.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];
    return features
        .whereType<Map<String, dynamic>>()
        .map(PlaceSearchResult.fromJson)
        .whereType<PlaceSearchResult>()
        .toList(growable: false);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close();
  }
}
