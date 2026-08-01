import 'article_details.dart';
import 'article_language.dart';

class ArticleSummaryCacheKey {
  const ArticleSummaryCacheKey(this.articleUrl, this.languageCode);

  factory ArticleSummaryCacheKey.forRequest(
    String articleUrl,
    ArticleLanguage language,
  ) => ArticleSummaryCacheKey(articleUrl.trim(), language.code);

  final String articleUrl;
  final String languageCode;

  @override
  bool operator ==(Object other) =>
      other is ArticleSummaryCacheKey &&
      other.articleUrl == articleUrl &&
      other.languageCode == languageCode;

  @override
  int get hashCode => Object.hash(articleUrl, languageCode);
}

class ArticleSummaryCache {
  final Map<ArticleSummaryCacheKey, ArticleDetails> _entries = {};

  ArticleDetails? get(ArticleSummaryCacheKey key) => _entries[key];

  void put(ArticleSummaryCacheKey key, ArticleDetails details) {
    _entries[key] = details;
  }

  int get length => _entries.length;
}
