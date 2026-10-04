import json
import socket
import unittest
from unittest.mock import Mock, patch

from article_source import public_target, download_html, extract_public_article
from article_cache import get_summary, put_summary, _values


class ArticleSourceTests(unittest.TestCase):
    def test_extracts_actual_jsonld_body(self):
        body = 'Reported facts from the original publisher. ' * 12
        html = '<script type="application/ld+json">' + json.dumps({
            '@type': 'NewsArticle', 'headline': 'Source title', 'articleBody': body,
        }) + '</script>'
        self.assertEqual(extract_public_article(html)[:2], ('Source title', body.strip()))

    def test_does_not_summarize_a_blocked_page(self):
        with self.assertRaises(ValueError):
            extract_public_article('<h1>Access denied</h1><p>Check your browser</p>')

    @patch('article_source.socket.getaddrinfo')
    def test_private_and_mixed_dns_answers_are_rejected(self, dns):
        for addresses in (['127.0.0.1'], ['169.254.169.254'], ['8.8.8.8', '10.0.0.1']):
            dns.return_value = [(socket.AF_INET, 1, 6, '', (ip, 443)) for ip in addresses]
            with self.assertRaises(ValueError):
                public_target('https://example.com/story')

    @patch('article_source.urllib3.HTTPSConnectionPool')
    @patch('article_source.socket.getaddrinfo')
    def test_redirect_is_revalidated_before_second_connection(self, dns, pool):
        dns.side_effect = [[(2, 1, 6, '', ('8.8.8.8', 443))], [(2, 1, 6, '', ('127.0.0.1', 443))]]
        response = Mock(status=302, headers={'Location': 'https://internal.example/secret'})
        pool.return_value.request.return_value = response
        with self.assertRaises(ValueError):
            download_html('https://example.com/story')
        self.assertEqual(pool.call_count, 1)
        self.assertEqual(pool.call_args.args[0], '8.8.8.8')
        self.assertEqual(pool.call_args.kwargs['assert_hostname'], 'example.com')
        response.close.assert_called_once()

    def test_cache_separates_languages_and_is_bounded(self):
        _values.clear()
        put_summary('story', 'en-US', {'title': 'English'})
        self.assertIsNone(get_summary('story', 'hi-IN'))
        self.assertEqual(get_summary('story', 'en-US')['title'], 'English')
        for i in range(140):
            put_summary(str(i), 'en-US', {'title': str(i)})
        self.assertEqual(len(_values), 128)


if __name__ == '__main__':
    unittest.main()
