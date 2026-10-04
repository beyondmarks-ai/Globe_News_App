import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../network/bounded_http.dart';

class NewsDemoError implements Exception {
  const NewsDemoError(this.message, this.code);
  final String message;
  final String code;
}

abstract interface class NewsDemoClient {
  Future<Map<String, dynamic>> status();
  Future<Map<String, dynamic>> ask(
    String question,
    String requestId,
    String? previousId,
  );
  Future<void> sendVerification();
  void dispose();
}

class NewsDemoApi implements NewsDemoClient {
  NewsDemoApi({
    required this.baseUrl,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken;
  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  static String newRequestId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Future<String?> _firebaseToken() async {
    await FirebaseAuth.instance.currentUser?.reload();
    return FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      if (body != null) {
        final token = await _tokenProvider();
        if (token == null) {
          throw const NewsDemoError('Please sign in again.', 'sign_in');
        }
        headers['Authorization'] = 'Bearer $token';
      }
      final base = Uri.tryParse(baseUrl);
      if (base == null ||
          !base.hasAuthority ||
          !{'https', 'http'}.contains(base.scheme)) {
        throw const NewsDemoError(
          'Demo service is not configured.',
          'unavailable',
        );
      }
      final response = await boundedRequest(
        _client,
        body == null ? 'GET' : 'POST',
        base.resolve('api/news-demo/$path'),
        headers: headers,
        body: body == null ? null : jsonEncode(body),
        timeout: Duration(seconds: body == null ? 12 : 120),
      );
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw NewsDemoError(
          json['error'] as String? ?? 'The demo is unavailable.',
          json['code'] as String? ?? 'unavailable',
        );
      }
      return json;
    } on NewsDemoError {
      rethrow;
    } catch (_) {
      throw const NewsDemoError(
        'Could not receive the answer. Retry the same request to check its status without using another question.',
        'connection',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> status() => _request('status');
  @override
  Future<Map<String, dynamic>> ask(
    String question,
    String requestId,
    String? previousId,
  ) => _request(
    'ask',
    body: {
      'question': question,
      'requestId': requestId,
      'previousId': previousId,
    },
  );
  @override
  Future<void> sendVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const NewsDemoError('Please sign in.', 'sign_in');
    await user.sendEmailVerification();
  }

  @override
  void dispose() => _client.close();
}
