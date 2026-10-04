import json
import unittest
from unittest.mock import patch

import azure.functions as func
import function_app
from topic_search import (create_archive, ingest_snapshot, search_archive,
    query_terms, canonical_url, InvalidSearch, ArchiveChanged, _set_meta)


class TopicSearchTests(unittest.TestCase):
    def setUp(self):
        self.db = create_archive()
        self.addCleanup(self.db.close)

    def ingest(self, records, date='2020-01-01T00:00:00+00:00'):
        ingest_snapshot(self.db, json.dumps(records), date)

    def test_natural_question_and_related_terms_match_across_dates(self):
        self.ingest([{'url': 'https://news.test/1', 'headline': 'Iranian missile conflict'}])
        self.ingest([{'url': 'https://news.test/2', 'headline': 'War in Iran'},
                     {'url': 'https://news.test/3', 'headline': 'War in Europe'}], '2026-10-04T00:00:00+00:00')
        result = search_archive(self.db, 'please show me news about war in Iran')
        self.assertEqual(result['total'], 2)
        self.assertEqual(result['coverage']['from'], '2020-01-01T00:00:00+00:00')
        self.assertEqual(result['keywords'], ['war', 'iran'])

    def test_deduplicates_urls_and_retains_oldest_date_and_real_headline(self):
        self.ingest([{'url':'https://news.test/iran?utm_source=app', 'headline':'Iran news', 'place':'Tehran'}])
        self.ingest([{'url':'https://news.test/iran#section', 'place':'Iran'}], '2026-01-01T00:00:00+00:00')
        result = search_archive(self.db, 'Iran')
        self.assertEqual(result['total'], 1)
        self.assertEqual(result['items'][0]['headline'], 'Iran news')
        self.assertTrue(result['items'][0]['firstSeen'].startswith('2020'))
        self.assertFalse(result['items'][0]['titleInferred'])

    def test_url_titles_are_explicitly_inferred_and_unsafe_links_rejected(self):
        self.ingest([{'url':'https://news.test/iran-war-update'}, {'url':'javascript:alert(1)'},
                     {'url':'https://user:pass@news.test/iran'}])
        result = search_archive(self.db, 'war in Iran')
        self.assertEqual(result['total'], 1)
        self.assertTrue(result['items'][0]['titleInferred'])

    def test_pagination_newest_and_no_duplicates(self):
        self.ingest([{'url':f'https://news.test/iran/{i}', 'headline':'Iran news'} for i in range(45)])
        self.ingest([{'url':'https://news.test/iran/new', 'headline':'Iran today'}], '2026-01-01T00:00:00+00:00')
        one = search_archive(self.db, 'Iran', 'newest')
        two = search_archive(self.db, 'Iran', 'newest', one['nextCursor'])
        three = search_archive(self.db, 'Iran', 'newest', two['nextCursor'])
        self.assertEqual(one['items'][0]['headline'], 'Iran today')
        self.assertEqual(len({i['url'] for p in (one,two,three) for i in p['items']}), 46)
        self.assertIsNone(three['nextCursor'])

    def test_cursor_bound_to_query_sort_and_archive_version(self):
        self.ingest([{'url':f'https://news.test/iran/{i}'} for i in range(25)])
        cursor = search_archive(self.db, 'Iran')['nextCursor']
        with self.assertRaises(InvalidSearch):
            search_archive(self.db, 'India', cursor=cursor)
        with self.assertRaises(InvalidSearch):
            search_archive(self.db, 'Iran', 'newest', cursor)
        _set_meta(self.db, 'version', 'new')
        with self.assertRaises(ArchiveChanged):
            search_archive(self.db, 'Iran', cursor=cursor)

    def test_rejects_empty_oversized_or_invalid_queries(self):
        for query in ('', '*', 'show me all news', 'a'*201):
            with self.assertRaises(InvalidSearch):
                query_terms(query)
        for cursor in ('!!!!', 'e30=', 'a'*513):
            with self.assertRaises(InvalidSearch):
                search_archive(self.db, 'Iran', cursor=cursor)
        with self.assertRaises(InvalidSearch):
            search_archive(self.db, 'Iran', sort='first_seen;drop table stories')

    def test_query_operators_cannot_inject_fts_or_sql(self):
        self.ingest([{'url':'https://news.test/iran', 'headline':'Iran war'}])
        self.assertEqual(search_archive(self.db, 'Iran OR war')['total'], 1)
        self.assertEqual(search_archive(self.db, 'Iran"; DROP TABLE stories; --')['total'], 0)
        self.assertEqual(search_archive(self.db, 'Iran')['total'], 1)

    def test_empty_archive_and_non_latin_query(self):
        self.assertEqual(search_archive(self.db, 'Iran')['total'], 0)
        self.ingest([{'url':'https://news.test/a', 'headline':'إيران أخبار'}])
        self.assertEqual(search_archive(self.db, 'إيران')['total'], 1)

    def test_nested_snapshot_and_canonical_url(self):
        self.ingest([{'data':[{'url':'https://news.test/iran'}]}])
        self.assertEqual(search_archive(self.db, 'Iran')['total'], 1)
        self.assertEqual(canonical_url('https://NEWS.test/a?id=2&utm_source=x#top'), 'https://news.test/a?id=2')

    @patch('function_app.search_topics')
    @patch.dict('os.environ', {'NEWS_ARCHIVE_ENABLED': 'true'})
    def test_route_returns_controlled_status_and_no_cache(self, search):
        handler = function_app.news_search.build().get_user_function()
        req = func.HttpRequest(method='GET', url='https://app/api/news-search', params={'q':'Iran'}, body=b'')
        for error, status in [(InvalidSearch('Invalid topic'),400), (ArchiveChanged(),409), (RuntimeError('secret'),503)]:
            search.side_effect = error
            response = handler(req)
            self.assertEqual(response.status_code, status)
            self.assertEqual(response.headers['Cache-Control'], 'no-store')
            self.assertNotIn('secret', response.get_body().decode())


if __name__ == '__main__':
    unittest.main()
