import 'dart:convert';

import 'package:http/http.dart' as http;

import '../network/bounded_http.dart';
import '../timeline/timeline_news_item.dart';

class TopicSearchException implements Exception {
  const TopicSearchException(this.message, {this.restart = false});
  final String message;
  final bool restart;
}

class TopicStory {
  TopicStory.fromJson(Map<String, dynamic> json)
    : firstSeen = DateTime.tryParse(json['firstSeen']?.toString() ?? ''),
      titleInferred = json['titleInferred'] == true,
      item = TimelineNewsItem(
        id: json['id'] as String,
        headline: json['headline'] as String,
        url: json['url'] as String,
        source: json['source'] as String? ?? '',
        place: json['place'] as String? ?? '',
        country: '',
        // Search results are not placed on the map; coordinates are optional.
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lon: (json['lon'] as num?)?.toDouble() ?? 0,
        tone: 0,
        color: 'unknown',
        hasEmbedding: false,
        aiReady: false,
        pulseStrength: 1,
      );
  final TimelineNewsItem item;
  final DateTime? firstSeen;
  final bool titleInferred;
}

class TopicSearchPage {
  TopicSearchPage.fromJson(Map<String, dynamic> json)
    : items = (json['items'] as List)
          .map((item) => TopicStory.fromJson(item as Map<String, dynamic>))
          .toList(),
      total = json['total'] as int,
      nextCursor = json['nextCursor'] as String?,
      coverage = json['coverage'] as Map<String, dynamic>;
  final List<TopicStory> items;
  final int total;
  final String? nextCursor;
  final Map<String, dynamic> coverage;
}

abstract interface class TopicSearchClient {
  Future<TopicSearchPage> search(String query, String sort, String? cursor);
  void cancel();
  void dispose();
}

class TopicSearchApi implements TopicSearchClient {
  TopicSearchApi({required this.baseUrl, http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final String baseUrl;
  final http.Client Function() _clientFactory;
  http.Client? _client;

  @override
  Future<TopicSearchPage> search(
    String query,
    String sort,
    String? cursor,
  ) async {
    cancel();
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        !{'http', 'https'}.contains(base.scheme)) {
      throw const TopicSearchException('News search is not configured.');
    }
    final client = _clientFactory();
    _client = client;
    try {
      final response = await boundedRequest(
        client,
        'GET',
        base
            .resolve('api/news-search')
            .replace(
              queryParameters: {'q': query, 'sort': sort, 'cursor': ?cursor},
            ),
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(seconds: 18),
      );
      if (response.statusCode == 409) {
        throw const TopicSearchException(
          'The archive has new stories. Search again to refresh results.',
          restart: true,
        );
      }
      if (response.statusCode == 400) {
        throw const TopicSearchException(
          'Try a specific topic using 2–200 characters and up to 12 keywords.',
        );
      }
      if (response.statusCode != 200) {
        throw const TopicSearchException(
          'News search is temporarily unavailable. Please retry.',
        );
      }
      return TopicSearchPage.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on TopicSearchException {
      rethrow;
    } catch (_) {
      throw const TopicSearchException(
        'Could not load news. Check your connection and retry.',
      );
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  @override
  void cancel() {
    _client?.close();
    _client = null;
  }

  @override
  void dispose() => cancel();
}
