import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:globe_news_beta/network/bounded_http.dart';

class HangingClient extends http.BaseClient {
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await (request as http.AbortableRequest).abortTrigger;
    aborted = true;
    throw http.ClientException('aborted');
  }
}

void main() {
  final uri = Uri.parse('https://example.com/api');
  test('transient failure retries but credential rejection does not', () async {
    var calls = 0;
    final client = MockClient(
      (_) async => http.Response('', ++calls == 1 ? 503 : 200),
    );
    expect(
      (await boundedRequest(client, 'GET', uri, attempts: 2)).statusCode,
      200,
    );
    expect(calls, 2);
    calls = 0;
    final denied = MockClient((_) async {
      calls++;
      return http.Response('', 403);
    });
    expect(
      (await boundedRequest(denied, 'GET', uri, attempts: 2)).statusCode,
      403,
    );
    expect(calls, 1);
  });
  test('timeout aborts the underlying request', () async {
    final client = HangingClient();
    await expectLater(
      boundedRequest(
        client,
        'GET',
        uri,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.aborted, isTrue);
  });
  test('cancelled request never retries', () async {
    var calls = 0;
    var active = true;
    final client = MockClient((_) async {
      calls++;
      active = false;
      throw http.ClientException('closed');
    });
    await expectLater(
      boundedRequest(client, 'GET', uri, attempts: 2, isActive: () => active),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 1);
  });
}
