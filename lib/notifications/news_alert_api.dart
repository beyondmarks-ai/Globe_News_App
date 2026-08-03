import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'news_alert.dart';

class NewsAlertApiException implements Exception {
  const NewsAlertApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NewsAlertApi {
  NewsAlertApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<void> save({
    required NewsAlert alert,
    required String installationId,
    required String deviceSecret,
    required String fcmToken,
  }) async {
    final response = await _client
        .post(
          _endpoint(),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            ...alert.toJson(),
            'installationId': installationId,
            'deviceSecret': deviceSecret,
            'fcmToken': fcmToken,
            'platform': 'android',
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const NewsAlertApiException('Could not save this news alert.');
    }
  }

  Future<void> disable({
    required String installationId,
    required String deviceSecret,
  }) async {
    final response = await _client
        .delete(
          _endpoint(),
          headers: {
            'X-Installation-ID': installationId,
            'X-Device-Secret': deviceSecret,
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const NewsAlertApiException('Could not disable this news alert.');
    }
  }

  Uri _endpoint() {
    final value = baseUrl.trim();
    if (value.isEmpty) {
      throw const NewsAlertApiException(
        'The notification service is unavailable.',
      );
    }
    return Uri.parse(
      '${value.replaceFirst(RegExp(r'/+$'), '')}/api/news-alerts',
    );
  }

  void dispose() => _client.close();
}
