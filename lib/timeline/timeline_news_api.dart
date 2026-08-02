import 'dart:convert';

import 'package:http/http.dart' as http;

import 'timeline_news_item.dart';
import 'timeline_selection.dart';

class TimelineNewsApiException implements Exception {
  const TimelineNewsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TimelineNewsApi {
  TimelineNewsApi({required this.baseUrl});

  final String baseUrl;
  http.Client? _activeClient;
  bool _disposed = false;

  Future<List<TimelineNewsItem>> fetch(
    TimelineSelection selection, {
    bool preferCached = false,
  }) async {
    if (_disposed) {
      throw const TimelineNewsApiException('Timeline service is disposed.');
    }
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      throw const TimelineNewsApiException(
        'API_BASE_URL is missing. Configure the deployed website URL with --dart-define.',
      );
    }

    _activeClient?.close();
    final client = http.Client();
    _activeClient = client;
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final timelineUri = Uri.parse('$root/api/timeline-news').replace(
      queryParameters: {
        'date': selection.apiDate,
        'time': selection.apiTime,
        if (preferCached) 'prefer_cached': '1',
      },
    );
    final cityUri = Uri.parse('$root/api/city-news/map');

    try {
      final cityFuture = _optionalGet(client, cityUri);
      final response = await client
          .get(timelineUri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 120));
      final cityResponse = await cityFuture;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TimelineNewsApiException(
          'Timeline request failed (${response.statusCode}).',
        );
      }
      final timelineDecoded = jsonDecode(response.body);
      final cityDecoded =
          cityResponse != null &&
              cityResponse.statusCode >= 200 &&
              cityResponse.statusCode < 300
          ? jsonDecode(cityResponse.body)
          : null;
      return mergeNewsResponses(cityDecoded, timelineDecoded);
    } on TimelineNewsApiException {
      rethrow;
    } on FormatException {
      throw const TimelineNewsApiException(
        'Timeline response is not valid JSON.',
      );
    } catch (error) {
      if (_disposed || !identical(client, _activeClient)) {
        throw const TimelineNewsApiException('Timeline request was cancelled.');
      }
      throw TimelineNewsApiException('Unable to load timeline news: $error');
    } finally {
      if (identical(client, _activeClient)) _activeClient = null;
      client.close();
    }
  }

  Future<http.Response?> _optionalGet(http.Client client, Uri uri) async {
    try {
      return await client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      if (_disposed || !identical(client, _activeClient)) rethrow;
      return null;
    }
  }

  void cancel() {
    _activeClient?.close();
    _activeClient = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}

List<TimelineNewsItem> mergeNewsResponses(Object? city, Object? timeline) {
  final items = <TimelineNewsItem>[];
  final ids = <String>{};
  for (final response in [city, timeline]) {
    for (final record in timelineRecordsFromResponse(response)) {
      final item = TimelineNewsItem.tryParse(record);
      if (item == null || !ids.add(item.id)) continue;
      items.add(item);
      if (items.length == 1000) return items;
    }
  }
  return items;
}

Iterable<Object?> timelineRecordsFromResponse(Object? decoded) sync* {
  if (decoded is List) {
    for (final value in decoded) {
      if (value is Map && value['data'] is List) {
        yield* value['data'] as List;
      } else {
        yield value;
      }
    }
    return;
  }
  if (decoded is Map) {
    for (final key in const ['items', 'data', 'news', 'results']) {
      final value = decoded[key];
      if (value is List) {
        yield* timelineRecordsFromResponse(value);
        return;
      }
    }
  }
}
