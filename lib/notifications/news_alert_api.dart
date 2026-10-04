import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'news_alert.dart';
import '../network/bounded_http.dart';

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
  bool _disposed = false;

  Future<void> save({
    required NewsAlert alert,
    required String installationId,
    required String deviceSecret,
    required String fcmToken,
  }) async {
    final response = await boundedRequest(
      _client,
      'POST',
      _endpoint(),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        ...alert.toJson(),
        'installationId': installationId,
        'deviceSecret': deviceSecret,
        'fcmToken': fcmToken,
        'platform': 'android',
      }),
      attempts: 2,
      isActive: () => !_disposed,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NewsAlertApiException(
        response.statusCode == 503
            ? 'Notification delivery is unavailable. Retry shortly; the server may need its Firebase configuration checked.'
            : 'Could not save this news alert. Please retry.',
      );
    }
    final result = jsonDecode(response.body);
    if (result is! Map || result['saved'] != true) {
      throw const NewsAlertApiException(
        'The server did not confirm notification registration.',
      );
    }
  }

  Future<void> disable({
    required String installationId,
    required String deviceSecret,
  }) async {
    final response = await boundedRequest(
      _client,
      'DELETE',
      _endpoint(),
      headers: {
        'X-Installation-ID': installationId,
        'X-Device-Secret': deviceSecret,
      },
      attempts: 2,
      isActive: () => !_disposed,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404) return; // Already disabled.
      throw const NewsAlertApiException('Could not disable this news alert.');
    }
  }

  Future<String> sendTest({
    required String installationId,
    required String deviceSecret,
  }) async {
    final response = await boundedRequest(
      _client,
      'POST',
      Uri.parse('${_endpoint()}/test'),
      headers: {
        'X-Installation-ID': installationId,
        'X-Device-Secret': deviceSecret,
      },
      timeout: const Duration(seconds: 35),
    );
    if (response.statusCode == 429) {
      throw const NewsAlertApiException(
        'Wait one minute before sending another test.',
      );
    }
    if (response.statusCode == 404) {
      throw const NewsAlertApiException(
        'Notification test is unavailable. Deploy the updated backend and reconnect alerts.',
      );
    }
    if (response.statusCode != 200) {
      throw const NewsAlertApiException(
        'Test delivery failed. The server Firebase sender configuration needs checking.',
      );
    }
    final result = jsonDecode(response.body);
    if (result is! Map ||
        result['accepted'] != true ||
        result['messageId'] is! String ||
        result['testId'] is! String) {
      throw const NewsAlertApiException(
        'The server did not confirm sending the test.',
      );
    }
    return result['testId'] as String;
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

  void dispose() {
    _disposed = true;
    _client.close();
  }
}
