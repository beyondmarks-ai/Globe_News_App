import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/article/article_details.dart';
import 'package:globe_news_beta/article/article_details_api.dart';
import 'package:globe_news_beta/article/article_language.dart';
import 'package:globe_news_beta/article/article_summary_cache.dart';
import 'package:globe_news_beta/article/article_summary_controller.dart';
import 'package:globe_news_beta/timeline/timeline_news_item.dart';

void main() {
  test('an older request cannot replace a newer language response', () async {
    final first = Completer<ArticleDetails>();
    final second = Completer<ArticleDetails>();
    final api = _QueuedArticleClient([first, second]);
    final controller = ArticleSummaryController(
      item: _item,
      api: api,
      cache: ArticleSummaryCache(),
    );
    addTearDown(controller.dispose);

    final firstLoad = controller.load();
    final secondLoad = controller.selectLanguage(ArticleLanguage.hindi);
    second.complete(_details('Hindi result'));
    await secondLoad;
    first.complete(_details('Old English result'));
    await firstLoad;

    expect(controller.language, ArticleLanguage.hindi);
    expect(controller.details?.title, 'Hindi result');
    expect(controller.status, ArticleSummaryStatus.ready);
  });

  test(
    'caches each language independently and reuses cached results',
    () async {
      final api = _ImmediateArticleClient();
      final cache = ArticleSummaryCache();
      final controller = ArticleSummaryController(
        item: _item,
        api: api,
        cache: cache,
      );
      addTearDown(controller.dispose);

      await controller.load();
      await controller.selectLanguage(ArticleLanguage.kannada);
      await controller.selectLanguage(ArticleLanguage.english);

      expect(api.calls, ['en-US', 'kn-IN']);
      expect(cache.length, 2);
      expect(controller.details?.title, 'en-US title');
    },
  );
}

const _item = TimelineNewsItem(
  id: 'story-1',
  place: 'Bidar',
  country: 'India',
  lat: 17.91,
  lon: 77.51,
  tone: -3.2,
  color: 'red',
  url: 'https://example.com/story',
  source: 'Example News',
  hasEmbedding: true,
  aiReady: true,
  pulseStrength: 1,
);

ArticleDetails _details(String title) => ArticleDetails(
  title: title,
  emoji: '📰',
  whatHappened: 'What happened',
  when: 'Today',
  where: 'Bidar',
  why: 'Reason',
  how: 'Method',
);

class _QueuedArticleClient implements ArticleDetailsClient {
  _QueuedArticleClient(this.responses);

  final List<Completer<ArticleDetails>> responses;
  int _index = 0;

  @override
  Future<ArticleDetails> fetch({
    required String articleUrl,
    required ArticleLanguage language,
  }) => responses[_index++].future;

  @override
  void cancel() {}

  @override
  void dispose() {}
}

class _ImmediateArticleClient implements ArticleDetailsClient {
  final List<String> calls = [];

  @override
  Future<ArticleDetails> fetch({
    required String articleUrl,
    required ArticleLanguage language,
  }) async {
    calls.add(language.code);
    return _details('${language.code} title');
  }

  @override
  void cancel() {}

  @override
  void dispose() {}
}
