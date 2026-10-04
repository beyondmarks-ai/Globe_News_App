import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:globe_news_beta/topic_search/topic_search_api.dart';
import 'package:globe_news_beta/topic_search/topic_search_controller.dart';
import 'package:globe_news_beta/topic_search/topic_search_screen.dart';

Map<String, dynamic> payload({String title = 'War in Iran', String? cursor}) =>
    {
      'items': [
        {
          'id': '1',
          'headline': title,
          'url': 'https://news.test/iran',
          'source': 'News',
          'firstSeen': '2020-01-01T00:00:00Z',
          'titleInferred': false,
        },
      ],
      'total': 1,
      'nextCursor': cursor,
      'coverage': {
        'from': '2020-01-01T00:00:00Z',
        'to': '2026-10-04T00:00:00Z',
        'backfillComplete': true,
      },
    };

class FakeSearch implements TopicSearchClient {
  final pending = <Completer<TopicSearchPage>>[];
  final queries = <String>[];
  @override
  Future<TopicSearchPage> search(String query, String sort, String? cursor) {
    queries.add(query);
    final c = Completer<TopicSearchPage>();
    pending.add(c);
    return c.future;
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

void main() {
  test('API encodes query and sends no date constraint', () async {
    final api = TopicSearchApi(
      baseUrl: 'https://app.test/',
      clientFactory: () => MockClient((request) async {
        expect(request.url.path, '/api/news-search');
        expect(request.url.queryParameters, {
          'q': 'war in Iran',
          'sort': 'relevance',
        });
        return http.Response(jsonEncode(payload()), 200);
      }),
    );
    final result = await api.search('war in Iran', 'relevance', null);
    expect(result.items.single.item.headline, 'War in Iran');
    expect(result.items.single.firstSeen?.year, 2020);
  });

  test('archive change requires a new search', () async {
    final api = TopicSearchApi(
      baseUrl: 'https://app.test/',
      clientFactory: () => MockClient((_) async => http.Response('{}', 409)),
    );
    await expectLater(
      api.search('Iran', 'newest', 'cursor'),
      throwsA(
        isA<TopicSearchException>().having((e) => e.restart, 'restart', true),
      ),
    );
  });

  test(
    'malformed response and unavailable service produce safe errors',
    () async {
      for (final response in [
        http.Response('invalid', 200),
        http.Response('secret', 503),
      ]) {
        final api = TopicSearchApi(
          baseUrl: 'https://app.test/',
          clientFactory: () => MockClient((_) async => response),
        );
        await expectLater(
          api.search('Iran', 'relevance', null),
          throwsA(isA<TopicSearchException>()),
        );
      }
    },
  );

  test(
    'late responses cannot overwrite a newer topic or edited input',
    () async {
      final api = FakeSearch();
      final controller = TopicSearchController(api);
      final first = controller.search('Iran');
      final second = controller.search('India');
      api.pending[1].complete(
        TopicSearchPage.fromJson(payload(title: 'India')),
      );
      await second;
      api.pending[0].complete(TopicSearchPage.fromJson(payload()));
      await first;
      expect(controller.items.single.item.headline, 'India');
      final third = controller.search('Iran');
      controller.edit();
      api.pending[2].complete(TopicSearchPage.fromJson(payload()));
      await third;
      expect(controller.items, isEmpty);
      expect(controller.searched, isFalse);
      controller.dispose();
    },
  );

  test(
    'pagination preserves articles on failure and deduplicates on retry',
    () async {
      final api = FakeSearch();
      final controller = TopicSearchController(api);
      var future = controller.search('Iran');
      api.pending.last.complete(
        TopicSearchPage.fromJson(payload(cursor: 'next')),
      );
      await future;
      future = controller.search('Iran', more: true);
      api.pending.last.completeError(const TopicSearchException('Retry'));
      await future;
      expect(controller.items, hasLength(1));
      expect(controller.cursor, 'next');
      future = controller.search('Iran', more: true);
      api.pending.last.complete(TopicSearchPage.fromJson(payload()));
      await future;
      expect(controller.items, hasLength(1));
      expect(controller.cursor, isNull);
      controller.dispose();
    },
  );

  test(
    'invalid input does not issue requests and disposal ignores completion',
    () async {
      final api = FakeSearch();
      final controller = TopicSearchController(api);
      await controller.search('a');
      expect(api.queries, isEmpty);
      final future = controller.search('Iran');
      controller.dispose();
      api.pending.last.complete(TopicSearchPage.fromJson(payload()));
      await future;
    },
  );

  testWidgets(
    'topic screen searches without dates and explains archive coverage',
    (tester) async {
      final api = FakeSearch();
      await tester.pumpWidget(
        MaterialApp(
          home: TopicSearchScreen(apiBaseUrl: 'https://app.test/', client: api),
        ),
      );
      expect(find.text('Any time'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('topic-query')),
        'war in Iran',
      );
      await tester.tap(find.byKey(const Key('topic-submit')));
      await tester.pump();
      expect(api.queries, ['war in Iran']);
      api.pending.last.complete(TopicSearchPage.fromJson(payload()));
      await tester.pumpAndSettle();
      expect(find.text('War in Iran'), findsOneWidget);
      expect(find.textContaining('not publication dates'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small screen with keyboard has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: TopicSearchScreen(
          apiBaseUrl: 'https://app.test/',
          client: FakeSearch(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
