import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/article/article_details.dart';
import 'package:globe_news_beta/article/article_language.dart';
import 'package:globe_news_beta/article/article_summary_cache.dart';

void main() {
  test('parses the structured article details response', () {
    final details = ArticleDetails.fromJson({
      'title': 'Short headline',
      'emoji': '🌍',
      'whatHappened': 'Something happened.',
      'when': 'Today',
      'where': 'India',
      'why': 'A stated reason',
      'how': 'A stated method',
      'imageUrl': 'https://example.com/image.jpg',
    });

    expect(details.title, 'Short headline');
    expect(details.whatHappened, 'Something happened.');
    expect(details.imageUri?.scheme, 'https');
  });

  test('supports a missing optional imageUrl', () {
    final details = ArticleDetails.fromJson(const {'title': 'Headline'});

    expect(details.imageUrl, isNull);
    expect(details.imageUri, isNull);
  });

  test('rejects invalid image and article URLs', () {
    final details = ArticleDetails.fromJson(const {
      'imageUrl': 'javascript:alert(1)',
    });

    expect(details.imageUrl, isNull);
    expect(validatedHttpUri('javascript:alert(1)'), isNull);
    expect(validatedHttpUri('file:///tmp/story'), isNull);
    expect(validatedHttpUri('https://example.com/story'), isNotNull);
  });

  test('cache key contains both URL and selected language', () {
    final english = ArticleSummaryCacheKey.forRequest(
      ' https://example.com/story ',
      ArticleLanguage.english,
    );
    final hindi = ArticleSummaryCacheKey.forRequest(
      'https://example.com/story',
      ArticleLanguage.hindi,
    );

    expect(english.articleUrl, 'https://example.com/story');
    expect(english.languageCode, 'en-US');
    expect(english, isNot(hindi));
  });
}
