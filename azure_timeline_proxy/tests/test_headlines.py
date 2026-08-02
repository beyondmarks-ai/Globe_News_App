import unittest
from unittest.mock import Mock, patch

from bidar_news.headlines import attach_indexed_headlines


class IndexedHeadlineTests(unittest.TestCase):
    @patch('bidar_news.headlines.requests.post')
    def test_joins_stored_titles_by_url_without_firecrawl(self, post):
        response = Mock()
        response.raise_for_status.return_value = None
        response.json.return_value = {
            'value': [
                {'url': 'https://example.com/a', 'title': 'Stored GDELT title'},
                {'url': 'https://example.com/b', 'title': 'ERROR: blocked'},
            ]
        }
        post.return_value = response

        result = attach_indexed_headlines(
            [
                {'url': 'https://example.com/a', 'place': 'Bidar'},
                {'url': 'https://example.com/b', 'place': 'London'},
            ],
            'https://search.example.com',
            'news-index',
            'server-key',
        )

        self.assertEqual(result[0]['headline'], 'Stored GDELT title')
        self.assertNotIn('headline', result[1])
        request = post.call_args.kwargs
        self.assertEqual(request['json']['select'], 'url,title')
        self.assertNotIn('server-key', str(result))

    @patch('bidar_news.headlines.requests.post')
    def test_missing_configuration_skips_search_request(self, post):
        records = [{'url': 'https://example.com/a'}]
        self.assertIs(
            attach_indexed_headlines(records, '', '', ''),
            records,
        )
        post.assert_not_called()

    @patch('bidar_news.headlines.requests.post')
    def test_existing_headline_is_preserved(self, post):
        response = Mock()
        response.raise_for_status.return_value = None
        response.json.return_value = {
            'value': [{'url': 'https://example.com/a', 'title': 'Indexed'}]
        }
        post.return_value = response
        result = attach_indexed_headlines(
            [{'url': 'https://example.com/a', 'headline': 'Upstream'}],
            'https://search.example.com',
            'news-index',
            'server-key',
        )
        self.assertEqual(result[0]['headline'], 'Upstream')


if __name__ == '__main__':
    unittest.main()
