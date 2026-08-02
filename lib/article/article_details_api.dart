import 'dart:convert';

import 'package:http/http.dart' as http;

import 'article_details.dart';
import 'article_language.dart';

class ArticleDetailsApiException implements Exception {
  const ArticleDetailsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ArticleDetailsClient {
  Future<ArticleDetails> fetch({
    required String articleUrl,
    required ArticleLanguage language,
  });

  void cancel();
  void dispose();
}

class ArticleDetailsApi implements ArticleDetailsClient {
  ArticleDetailsApi({required this.baseUrl});

  final String baseUrl;
  http.Client? _activeClient;
  bool _disposed = false;

  @override
  Future<ArticleDetails> fetch({
    required String articleUrl,
    required ArticleLanguage language,
  }) async {
    if (_disposed) {
      throw const ArticleDetailsApiException('Article service is disposed.');
    }
    final articleUri = validatedHttpUri(articleUrl);
    if (articleUri == null) {
      throw const ArticleDetailsApiException('Invalid article URL.');
    }
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      throw const ArticleDetailsApiException('Article service is unavailable.');
    }

    _activeClient?.close();
    final client = http.Client();
    _activeClient = client;
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$root/api/article-details');
    final cityId = cityNewsIdFromArticleUri(articleUri);
    if (language == ArticleLanguage.english && cityId != null) {
      final cityDetails = await _fetchCityDetails(client, root, cityId);
      if (cityDetails != null) {
        if (identical(client, _activeClient)) _activeClient = null;
        client.close();
        return cityDetails;
      }
    }

    try {
      final response = await client
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'url': articleUri.toString(),
              'language': language.code,
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ArticleDetailsApiException(
          'This article could not be summarized.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const ArticleDetailsApiException(
          'This article could not be summarized.',
        );
      }
      return ArticleDetails.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on ArticleDetailsApiException {
      rethrow;
    } on FormatException {
      throw const ArticleDetailsApiException(
        'This article could not be summarized.',
      );
    } catch (_) {
      if (_disposed || !identical(client, _activeClient)) {
        throw const ArticleDetailsApiException('Request cancelled.');
      }
      throw const ArticleDetailsApiException(
        'This article could not be summarized.',
      );
    } finally {
      if (identical(client, _activeClient)) _activeClient = null;
      client.close();
    }
  }

  Future<ArticleDetails?> _fetchCityDetails(
    http.Client client,
    String root,
    String cityId,
  ) async {
    try {
      final response = await client
          .get(
            Uri.parse('$root/api/city-news/$cityId'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return ArticleDetails.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      if (_disposed || !identical(client, _activeClient)) rethrow;
      return null;
    }
  }

  @override
  void cancel() {
    _activeClient?.close();
    _activeClient = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
  }
}

String? cityNewsIdFromArticleUri(Uri uri) {
  if (uri.host != 'vijaykarnataka.com' &&
      uri.host != 'www.vijaykarnataka.com') {
    return null;
  }
  final match = RegExp(r'/articleshow/(\d+)\.cms$').firstMatch(uri.path);
  return match == null ? null : 'bidar-vk-${match.group(1)}';
}
