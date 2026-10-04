import 'dart:async';
import 'package:http/http.dart' as http;

/// Abort timed-out work; Future.timeout alone leaves the HTTP request running.
Future<http.Response> boundedRequest(
  http.Client client,
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  String? body,
  Duration timeout = const Duration(seconds: 12),
  int attempts = 1,
  bool Function()? isActive,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (isActive != null && !isActive()) {
      throw http.ClientException('Request cancelled.');
    }
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    )..headers.addAll(headers);
    if (body != null) request.body = body;
    try {
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            timeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException('The service took too long to respond.');
            },
          );
      if (!{502, 503, 504}.contains(response.statusCode) ||
          attempt + 1 == attempts) {
        return response;
      }
    } on TimeoutException {
      if (attempt + 1 == attempts) rethrow;
    } on http.ClientException {
      if (attempt + 1 == attempts || (isActive != null && !isActive())) rethrow;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('At least one HTTP attempt is required.');
}
