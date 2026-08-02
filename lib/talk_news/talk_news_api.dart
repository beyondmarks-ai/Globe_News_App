import 'dart:convert';

import 'package:http/http.dart' as http;

import '../timeline/timeline_news_item.dart';
import 'talk_news_preferences.dart';
import 'talk_news_session.dart';

abstract interface class TalkNewsSessionClient {
  Future<TalkNewsSession> createSession({
    required TimelineNewsItem item,
    required String title,
    required TalkNewsLanguage language,
    required TalkNewsVoice voice,
  });

  void dispose();
}

class TalkNewsApi implements TalkNewsSessionClient {
  TalkNewsApi({required String baseUrl, http.Client? client})
    : _baseUri = Uri.tryParse(baseUrl.trim()),
      _client = client ?? http.Client();

  final Uri? _baseUri;
  final http.Client _client;
  bool _disposed = false;

  @override
  Future<TalkNewsSession> createSession({
    required TimelineNewsItem item,
    required String title,
    required TalkNewsLanguage language,
    required TalkNewsVoice voice,
  }) async {
    if (_disposed) throw StateError('Talk-news API is disposed');
    final base = _baseUri;
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      throw const TalkNewsApiException('Voice service is not configured.');
    }
    final normalized = base.toString().endsWith('/')
        ? base.toString().substring(0, base.toString().length - 1)
        : base.toString();
    final response = await _client
        .post(
          Uri.parse('$normalized/api/talk-news/session'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'articleId': item.id,
            'url': item.url,
            'title': title,
            'source': item.source,
            'place': item.place,
            'country': item.country,
            'tone': item.tone,
            'language': language.code,
            'voice': voice.id,
          }),
        )
        .timeout(const Duration(seconds: 35));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const TalkNewsApiException(
        'Talk to this news is temporarily unavailable.',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const TalkNewsApiException(
        'The voice session response was invalid.',
      );
    }
    try {
      return TalkNewsSession.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      throw const TalkNewsApiException(
        'The voice session response was invalid.',
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close();
  }
}

class TalkNewsApiException implements Exception {
  const TalkNewsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
