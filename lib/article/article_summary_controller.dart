import 'package:flutter/foundation.dart';

import '../timeline/timeline_news_item.dart';
import 'article_details.dart';
import 'article_details_api.dart';
import 'article_language.dart';
import 'article_summary_cache.dart';

enum ArticleSummaryStatus { idle, loading, ready, error }

class ArticleSummaryController extends ChangeNotifier {
  ArticleSummaryController({
    required this.item,
    required ArticleDetailsClient api,
    required ArticleSummaryCache cache,
    ArticleLanguage initialLanguage = ArticleLanguage.english,
  }) : _api = api,
       _cache = cache,
       _language = initialLanguage;

  final TimelineNewsItem item;
  final ArticleDetailsClient _api;
  final ArticleSummaryCache _cache;

  ArticleLanguage _language;
  ArticleSummaryStatus _status = ArticleSummaryStatus.idle;
  ArticleDetails? _details;
  String? _error;
  bool _disposed = false;
  int _requestGeneration = 0;

  ArticleLanguage get language => _language;
  ArticleSummaryStatus get status => _status;
  ArticleDetails? get details => _details;
  String? get error => _error;
  bool get isLoading => _status == ArticleSummaryStatus.loading;

  Future<void> load({ArticleLanguage? language}) async {
    if (_disposed) return;
    if (language != null) _language = language;
    final generation = ++_requestGeneration;
    _error = null;
    _api.cancel();

    final key = ArticleSummaryCacheKey.forRequest(item.url, _language);
    final cached = _cache.get(key);
    if (cached != null) {
      _details = cached;
      _status = ArticleSummaryStatus.ready;
      notifyListeners();
      return;
    }

    _details = null;
    _status = ArticleSummaryStatus.loading;
    notifyListeners();
    try {
      final result = await _api.fetch(
        articleUrl: item.url,
        language: _language,
      );
      if (_disposed || generation != _requestGeneration) return;
      if (!result.isSourceExcerpt) _cache.put(key, result);
      _details = result;
      _status = ArticleSummaryStatus.ready;
    } catch (error) {
      if (_disposed || generation != _requestGeneration) return;
      _details = null;
      _error = error is ArticleDetailsApiException
          ? error.message
          : 'This article could not be summarized.';
      _status = ArticleSummaryStatus.error;
    } finally {
      if (!_disposed && generation == _requestGeneration) notifyListeners();
    }
  }

  Future<void> selectLanguage(ArticleLanguage language) async {
    if (_disposed || language == _language) return;
    await load(language: language);
  }

  Future<void> retry() => load();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestGeneration++;
    _api.dispose();
    super.dispose();
  }
}
