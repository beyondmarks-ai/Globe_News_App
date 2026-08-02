import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/talk_news/talk_news_api.dart';
import 'package:globe_news_beta/talk_news/talk_news_preferences.dart';
import 'package:globe_news_beta/timeline/timeline_news_item.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends full story grounding plus selected language and voice', () async {
    Map<String, Object?>? requestBody;
    final client = MockClient((request) async {
      requestBody = (jsonDecode(request.body) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      return http.Response(
        jsonEncode({
          'token': 'ephemeral',
          'webrtcUrl':
              'https://rakesh.openai.azure.com/openai/v1/realtime/calls?webrtcfilter=on',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = TalkNewsApi(baseUrl: 'https://api.example.com', client: client);
    addTearDown(api.dispose);

    await api.createSession(
      item: _item,
      title: 'Known headline',
      language: TalkNewsLanguage.kannada,
      voice: TalkNewsVoice.sage,
    );

    expect(requestBody?['articleId'], 'global-story-1');
    expect(requestBody?['url'], 'https://example.com/global-story');
    expect(requestBody?['language'], 'kn-IN');
    expect(requestBody?['voice'], 'sage');
    expect(requestBody?['place'], 'Paris');
  });
}

const _item = TimelineNewsItem(
  id: 'global-story-1',
  place: 'Paris',
  country: 'France',
  lat: 48.85,
  lon: 2.35,
  tone: -1,
  color: 'red',
  url: 'https://example.com/global-story',
  source: 'Global News',
  hasEmbedding: false,
  aiReady: false,
  pulseStrength: 1,
);
