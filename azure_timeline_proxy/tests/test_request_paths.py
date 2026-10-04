import json
import unittest
from unittest.mock import Mock, patch

import azure.functions as func
import function_app as app
from article_cache import _values


def handler(function):
    return function.build().get_user_function()


class RequestPathTests(unittest.TestCase):
    def test_errors_are_never_cached(self):
        self.assertEqual(app._response('{}', 503, 'MISS').headers['Cache-Control'], 'no-store')
        self.assertEqual(app._city_response({}, 503).headers['Cache-Control'], 'no-store')

    @patch.dict('os.environ', {'TIMELINE_NEWS_FUNCTION_KEY': 'test-key'})
    @patch('function_app._store_latest')
    @patch('function_app.requests.get')
    @patch('function_app._cache_blob')
    def test_cache_write_failure_keeps_successful_news_and_cannot_replace_latest(self, blob, get, latest):
        from azure.core.exceptions import ResourceNotFoundError
        blob.return_value.download_blob.side_effect = ResourceNotFoundError('missing')
        blob.return_value.upload_blob.side_effect = RuntimeError('storage unavailable')
        get.return_value.status_code = 200
        get.return_value.content = b'[{"id":"past-story"}]'
        request = func.HttpRequest(method='GET', url='http://localhost/api/timeline-news',
            params={'date': '2026-10-01', 'time': '03:30'}, body=b'')
        response = handler(app.timeline_news_proxy)(request)
        self.assertEqual(response.status_code, 200)
        latest.assert_not_called()

    @patch('function_app.attach_indexed_headlines')
    @patch('function_app._cache_blob')
    def test_cache_hit_does_not_make_headline_requests_or_blob_writes(self, blob, headlines):
        blob.return_value.download_blob.return_value.readall.return_value = b'[{"id":"a"}]'
        request = func.HttpRequest(method='GET', url='http://localhost/api/timeline-news',
            params={'date': '2026-10-04', 'time': '03:30'}, body=b'')
        response = handler(app.timeline_news_proxy)(request)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers['X-Timeline-Cache'], 'HIT')
        headlines.assert_not_called()
        blob.return_value.upload_blob.assert_not_called()

    @patch('function_app._validated_public_url', return_value='https://example.com/story')
    @patch('function_app._download_article', return_value=('Source title', 'Actual source text. ' * 30, None))
    @patch('function_app._summarize_article', side_effect=RuntimeError('AI configuration missing'))
    def test_summary_outage_returns_labeled_source_text_not_invented_facts(self, summarize, download, validate):
        _values.clear()
        request = func.HttpRequest(method='POST', url='http://localhost/api/article-details',
            body=json.dumps({'url': 'https://example.com/story', 'language': 'kn-IN'}).encode())
        response = handler(app.article_details)(request)
        payload = json.loads(response.get_body())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(payload['summaryKind'], 'source_excerpt')
        self.assertTrue(payload['whatHappened'].startswith('Actual source text.'))
        self.assertEqual(payload['where'], '')
        handler(app.article_details)(request)
        download.assert_called_once()

    @patch.dict('os.environ', {'AZURE_OPENAI_ENDPOINT': 'https://resource.example',
        'AZURE_OPENAI_KEY': 'test-key', 'AZURE_OPENAI_CHAT_DEPLOYMENT': 'configured-deployment'})
    @patch('function_app.requests.post')
    def test_summary_request_uses_current_token_parameter_and_validates_content(self, post):
        post.return_value.json.return_value = {'choices': [{'message': {'content': json.dumps({
            'title': 'Summary title', 'whatHappened': 'Supported facts'})}}]}
        result = app._summarize_article('https://example.com/story', 'en-US', 'Title', 'Source', None)
        payload = post.call_args.kwargs['json']
        self.assertIn('max_completion_tokens', payload)
        self.assertNotIn('max_tokens', payload)
        self.assertNotIn('temperature', payload)
        self.assertEqual(result['summaryKind'], 'ai')
