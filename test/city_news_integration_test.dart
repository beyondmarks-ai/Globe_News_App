import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/article/article_details_api.dart';
import 'package:globe_news_beta/timeline/timeline_news_api.dart';

void main() {
  test('city news is merged first and duplicate IDs are removed', () {
    final items = mergeNewsResponses(
      {
        'items': [_item('city-1', 17.9, 77.5)],
      },
      [_item('city-1', 0, 0), _item('global-1', 12.9, 77.6)],
    );

    expect(items.map((item) => item.id), ['city-1', 'global-1']);
    expect(items.first.lat, 17.9);
    expect(items.first.pulseReady, isTrue);
  });

  test('derives only authorized Vijaya Karnataka city-news IDs', () {
    expect(
      cityNewsIdFromArticleUri(
        Uri.parse(
          'https://vijaykarnataka.com/news/bidar/story/articleshow/132673264.cms',
        ),
      ),
      'bidar-vk-132673264',
    );
    expect(
      cityNewsIdFromArticleUri(
        Uri.parse('https://example.com/articleshow/132673264.cms'),
      ),
      isNull,
    );
  });
}

Map<String, Object> _item(String id, double lat, double lon) => {
  'id': id,
  'place': 'Bidar',
  'country': 'India',
  'lat': lat,
  'lon': lon,
  'tone': 0,
  'color': 'yellow',
  'url': 'https://example.com/$id',
  'source': 'Test',
  'has_embedding': true,
  'ai_ready': true,
};
