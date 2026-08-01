import 'dart:convert';

import 'package:http/http.dart' as http;

import 'place_search_result.dart';

abstract interface class PlaceSearchClient {
  Future<PlaceSearchResult?> search(String query);
  void dispose();
}

class PlaceSearchApi implements PlaceSearchClient {
  PlaceSearchApi({required this.accessToken, http.Client? client})
    : _client = client ?? http.Client();

  final String accessToken;
  final http.Client _client;
  bool _disposed = false;

  @override
  Future<PlaceSearchResult?> search(String query) async {
    final normalized = query.trim();
    if (_disposed) throw StateError('Place search has been disposed.');
    if (accessToken.isEmpty) throw StateError('Mapbox token is missing.');
    if (normalized.isEmpty ||
        normalized.length > 256 ||
        normalized.contains(';')) {
      return null;
    }

    final uri = Uri.https('api.mapbox.com', '/search/geocode/v6/forward', {
      'q': normalized,
      'access_token': accessToken,
      'autocomplete': 'false',
      'limit': '1',
      'types': 'country,region,district,place,locality,neighborhood',
      'language': 'en',
    });
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Place search failed.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final features = decoded['features'];
    if (features is! List || features.isEmpty) return null;
    final first = features.first;
    return first is Map<String, dynamic>
        ? PlaceSearchResult.fromJson(first)
        : null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close();
  }
}
