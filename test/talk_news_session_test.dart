import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/talk_news/talk_news_session.dart';

void main() {
  test('parses a valid Azure OpenAI realtime session', () {
    final session = TalkNewsSession.fromJson(const {
      'token': 'short-lived-secret',
      'webrtcUrl':
          'https://example.openai.azure.com/openai/v1/realtime/calls?webrtcfilter=on',
    });
    expect(session.token, 'short-lived-secret');
    expect(session.webrtcUri.scheme, 'https');
  });

  test('rejects non-Azure or insecure realtime URLs', () {
    expect(
      () => TalkNewsSession.fromJson(const {
        'token': 'secret',
        'webrtcUrl': 'https://evil.example/realtime',
      }),
      throwsFormatException,
    );
    expect(
      () => TalkNewsSession.fromJson(const {
        'token': 'secret',
        'webrtcUrl': 'http://example.openai.azure.com/realtime',
      }),
      throwsFormatException,
    );
  });
}
