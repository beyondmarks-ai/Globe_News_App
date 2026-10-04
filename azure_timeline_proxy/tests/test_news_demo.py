import json
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import Mock, patch

from azure.core.exceptions import ResourceNotFoundError, ResourceExistsError, ResourceModifiedError
import news_demo as demo


class MemoryBlob:
    def __init__(self):
        self.data = None
        self.version = 0
        self.lock = threading.Lock()

    def download_blob(self):
        with self.lock:
            if self.data is None:
                raise ResourceNotFoundError('missing')
            data = self.data
            return SimpleNamespace(readall=lambda: data, properties=SimpleNamespace(etag=str(self.version)))

    def upload_blob(self, data, overwrite=False, etag=None, **kwargs):
        with self.lock:
            if not overwrite and self.data is not None:
                raise ResourceExistsError('exists')
            if etag is not None and etag != str(self.version):
                raise ResourceModifiedError('changed')
            self.data = data
            self.version += 1


class DemoTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 4, 12, tzinfo=timezone.utc)
        self.env = patch.dict('os.environ', {'NEWS_DEMO_ENABLED':'true',
            'NEWS_DEMO_STARTS_AT':(self.now-timedelta(hours=1)).isoformat(),
            'FIREBASE_WEB_API_KEY':'test-key', 'FIRECRAWL_API_KEY':'test-key',
            'NEWS_OPENAI_ENDPOINT':'https://model.test', 'NEWS_OPENAI_KEY':'test-key',
            'NEWS_OPENAI_CHAT_DEPLOYMENT':'existing-model'})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.clock = patch('news_demo.utc_now', return_value=self.now)
        self.now_mock = self.clock.start()
        self.addCleanup(self.clock.stop)
        self.blob = MemoryBlob()
        storage = patch('news_demo.blob_service')
        storage.start().return_value.get_blob_client.return_value = self.blob
        self.addCleanup(storage.stop)
        # Unit tests must never fetch live publishers.
        articles = patch('news_demo.download_html', side_effect=ValueError('Publisher unavailable'))
        self.article_download = articles.start()
        self.addCleanup(articles.stop)

    def test_global_quota_survives_new_store_instances_and_never_refunds(self):
        for i in range(100):
            store=demo.DemoStore()
            result=store.reserve('user', f'{i:032x}', 'Iran news', None)
            store.finish(f'{i:032x}', {'topic':'Iran'}, failed=i%2 == 0)
            self.now += timedelta(seconds=61)
            self.now_mock.return_value = self.now
        self.assertEqual(result['remaining'], 0)
        with self.assertRaises(demo.DemoError) as error:
            demo.DemoStore().reserve('other', 'f'*32, 'India news', None)
        self.assertEqual(error.exception.code, 'quota_exhausted')

    @patch('news_demo.MAX_IN_FLIGHT', 3)
    def test_concurrent_reservations_do_not_overspend(self):
        for i in range(98):
            store=demo.DemoStore()
            store.reserve('user', f'{i:032x}', 'Iran', None)
            store.finish(f'{i:032x}', {})
            self.now += timedelta(seconds=61)
            self.now_mock.return_value = self.now
        def reserve(i):
            try:
                demo.DemoStore().reserve('user', f'{i:032x}', 'Iran', None)
                return True
            except demo.DemoError:
                return False
        with ThreadPoolExecutor(max_workers=8) as executor:
            results=list(executor.map(reserve, range(100, 120)))
        self.assertEqual(sum(results), 2)
        self.assertEqual(len(demo.DemoStore().read()[0]['requests']), 100)

    def test_idempotency_and_context_ownership(self):
        store=demo.DemoStore()
        store.reserve('a', 'a'*32, 'Iran', None)
        store.finish('a'*32, {'topic':'Iran'})
        duplicate=store.reserve('a', 'a'*32, 'Iran', None)
        self.assertEqual(duplicate['existing']['status'], 'done')
        self.assertEqual(duplicate['remaining'], 99)
        for uid, question in [('b','Iran'),('a','India')]:
            with self.assertRaises(demo.DemoError):
                store.reserve(uid,'a'*32,question,None)
        with self.assertRaises(demo.DemoError):
            store.reserve('b','b'*32,'Why?','a'*32)

    @patch('news_demo.requests.post')
    def test_account_created_before_demo_rejected_even_if_login_is_recent(self, post):
        post.return_value.status_code=200
        user={'localId':'a','emailVerified':True,'createdAt':str(int((self.now-timedelta(days=1)).timestamp()*1000))}
        post.return_value.json.return_value={'users':[user]}
        with self.assertRaises(demo.DemoError) as error:
            demo.authenticate('Bearer '+'x'*30)
        self.assertEqual(error.exception.code,'ineligible')
        user['createdAt']=str(int(self.now.timestamp()*1000))
        self.assertEqual(demo.authenticate('Bearer '+'x'*30),'a')
        user['emailVerified']=False
        with self.assertRaises(demo.DemoError) as error:
            demo.authenticate('Bearer '+'x'*30)
        self.assertEqual(error.exception.code,'verify_email')

    @patch('news_demo.requests.post')
    def test_expiry_and_disabled_gate_block_calls_before_auth(self, post):
        with patch('news_demo.utc_now',return_value=self.now+timedelta(hours=23)):
            with self.assertRaises(demo.DemoError):
                demo.authenticate('Bearer '+'x'*30)
        with patch.dict('os.environ',{'NEWS_DEMO_ENABLED':'false'}):
            with self.assertRaises(demo.DemoError):
                demo.authenticate('Bearer '+'x'*30)
        post.assert_not_called()

    @patch('news_demo.requests.post')
    def test_search_cost_is_bounded_and_never_enables_scraping(self, post):
        post.return_value.json.return_value={'success':True,'data':{'web':[{'url':'https://news.test/iran','description':'Iran report'}]*20}}
        self.assertEqual(len(demo.retrieve('Iran',True)),5)
        body=post.call_args.kwargs['json']
        self.assertEqual(body['limit'],5)
        self.assertEqual(body['tbs'],'qdr:d')
        self.assertNotIn('scrapeOptions',body)
        self.assertEqual(body['sources'],['web'])
        self.assertIn('-site:facebook.com',body['query'])
        self.assertLessEqual(len(body['query']),450)

    def test_event_date_search_hint_parses_iso_english_and_india_today(self):
        for question in ('2 October 2026','October 2, 2026','2nd Oct','2026-10-02'):
            self.assertEqual(demo.requested_event_date(question),'2026-10-02')
        self.assertIsNone(demo.requested_event_date('31 February 2026'))
        self.assertIsNone(demo.requested_event_date('why this happened'))
        self.assertEqual(demo.requested_event_date('today'),'2026-10-04')

    @patch('news_demo.ask_model')
    @patch('news_demo.retrieve')
    def test_citations_validated_and_searches_capped(self, retrieve, model):
        retrieve.return_value=[{'url':'https://news.test/a','title':'Iran report','excerpt':'The source supports this text.','date':'','kind':'recent_search'}]
        model.side_effect=[{'topic':'Iran','backgroundQuery':'Iran background'},
            {'sections':[{'heading':'How it began','text':'Supported','sourceIds':[1],
                          'support':['1.1']},
                         {'heading':'Where things stand','text':'Invented','sourceIds':[99]}]}]
        answer=demo.explain('Iran news',None)
        self.assertEqual(retrieve.call_count,2)
        self.assertEqual(model.call_count,2)
        self.assertEqual(len(answer['sources']),1)
        self.assertNotIn('excerpt',answer['sources'][0])
        self.assertEqual(len(answer['sections']),1)

    @patch('news_demo.ask_model')
    @patch('news_demo.retrieve')
    def test_dated_story_preserves_event_date_and_all_five_sections(self, retrieve, model):
        retrieve.return_value=[{'url':'https://news.test/a','title':'Report','excerpt':'The source supports this text.',
                                'date':'2026-10-03','kind':'background_search'}]
        model.side_effect=[{'topic':'Jantar Mantar 2 October 2026',
                            'backgroundQuery':'CEC voter roll revision origins timeline explained'},
            {'sections':[{'heading':heading,'text':'Supported dated passage','sourceIds':[1],
                          'support':['1.1']}
                         for heading in reversed(demo.STORY_HEADINGS)],'uncertainty':''}]
        result=demo.explain('Jantar Mantar protest on 2 October 2026',None)
        first=retrieve.call_args_list[0]
        self.assertIn('2 October 2026',first.args[0])
        self.assertFalse(first.args[1])  # No past-24h filter on a historical event.
        self.assertEqual(retrieve.call_args_list[1].args,
                         ('CEC voter roll revision origins timeline explained before:2026-10-02',False))
        self.assertEqual([s['heading'] for s in result['sections']],list(demo.STORY_HEADINGS))
        self.assertEqual(self.article_download.call_count,1)  # Duplicate URL not fetched again.
        prompt=model.call_args.args[0]
        self.assertIn('EVENT date',prompt)
        self.assertIn('deployed but not used',prompt)
        self.assertIn('official response or outcome are missing',prompt)
        self.assertEqual(model.call_args.kwargs['max_tokens'],1600)

    @patch('news_demo.ask_model')
    @patch('news_demo.retrieve')
    def test_fabricated_or_missing_passages_remove_sections_and_disclose_gap(self, retrieve, model):
        retrieve.return_value=[{'url':'https://news.test/a','title':'Report',
                                'excerpt':'Police deployed equipment but did not use it.','date':'','kind':'event_search'}]
        model.side_effect=[{'topic':'Protest','backgroundQuery':'policy history'},
            {'sections':[
                {'heading':'How it began','text':'Invented claim','sourceIds':[1],
                 'support':['99.1']},
                {'heading':'How it developed','text':'Unquoted claim','sourceIds':[1]},
                {'heading':'The event you asked about','text':'Equipment was deployed but not used.',
                 'sourceIds':[1],'support':['1.1']}]}]
        result=demo.explain('Protest history',None)
        self.assertEqual(len(result['sections']),1)
        self.assertEqual(result['sections'][0]['heading'],'The event you asked about')
        self.assertIn('source passages could not be verified',result['uncertainty'])
        self.assertNotIn('support',result['sections'][0])

    def test_passage_ids_preserve_attribution_and_resolve_to_verbatim_paragraphs(self):
        evidence, passages=demo.source_passages([{'id':4,'url':'https://news.test/story',
            'title':'News','excerpt':'Equipment was deployed but not used. Mr. Kumar denied wrongdoing.\nOfficials denied the allegation.'}])
        self.assertEqual(passages['4.1']['quote'],'Equipment was deployed but not used. Mr. Kumar denied wrongdoing.')
        self.assertEqual(passages['4.2']['sourceId'],4)
        self.assertNotIn('url',evidence[0])
        self.assertEqual(evidence[0]['passages'][1]['text'],'Officials denied the allegation.')

    def test_search_excerpt_discards_images_urls_and_block_pages(self):
        raw='![photo](https://news.test/image.png)\n[Headline](https://news.test/a)\nActual report. Missing: history query'
        self.assertEqual(demo.clean_search_excerpt(raw),'Headline Actual report.')
        self.assertEqual(demo.clean_search_excerpt('# example.com is blocked ![](data:image/png;base64,xyz)'), '')
        self.assertLessEqual(len(demo.clean_search_excerpt('text '*1000)),800)

    @patch('news_demo.ask_model',return_value={'clarification':'Which event?'})
    @patch('news_demo.retrieve',return_value=[])
    def test_search_excludes_story_instructions_after_question(self, retrieve, model):
        demo.explain('Jantar Mantar on 2 October 2026? Tell the story from beginning to end.',None)
        self.assertIn('2 October 2026',retrieve.call_args.args[0])
        self.assertNotIn('beginning',retrieve.call_args.args[0])

    def test_public_reading_prefers_requested_event_over_unrelated_first_result(self):
        sources=[{'url':'https://news.test/mumbai','title':'Mumbai protest','excerpt':'Mumbai news'},
                 {'url':'https://news.test/delhi','title':'Jantar Mantar protest','excerpt':'Jantar Mantar news'}]
        demo.enrich_sources(sources,'Jantar Mantar protest',1)
        self.article_download.assert_called_once_with('https://news.test/delhi')

    @patch('news_demo.ask_model')
    @patch('news_demo.retrieve')
    def test_story_context_keeps_origins_and_outcome_for_followups(self, retrieve, model):
        retrieve.return_value=[]
        previous={'topic':'CEC resignation dispute','sections':[
            {'heading':h,'text':'Context, not evidence'} for h in demo.STORY_HEADINGS]}
        model.return_value={'topic':'CEC resignation dispute','backgroundQuery':'voter revision history'}
        result=demo.explain('Why his resignation?',previous)
        self.assertIn('CEC resignation dispute',retrieve.call_args_list[0].args[0])
        self.assertEqual(len(model.call_args.args[1]['previous']['sections']),5)
        self.assertEqual(result['sections'],[])
        model.assert_called_once()  # No evidence: do not generate a story.

    @patch('news_demo.ask_model',return_value={'clarification':'Which protest?'})
    @patch('news_demo.retrieve',return_value=[])
    def test_today_query_uses_india_calendar_date(self, retrieve, model):
        self.now_mock.return_value=self.now.replace(hour=20)
        demo.explain('protest today',None)
        self.assertIn('2026-10-05',retrieve.call_args.args[0])

    @patch('news_demo.extract_public_article',return_value=('Full title','Opening context.\nEarlier policy caused objections.',None))
    def test_public_reading_bounded_skips_social_and_marks_passages(self, extract):
        self.article_download.side_effect=None
        self.article_download.return_value=b'<html>public article</html>'
        sources=[{'url':u,'excerpt':'Search snippet','evidenceType':'search_excerpt'} for u in
                 ['https://www.facebook.com/post','https://news.test/1','https://news.test/2','https://news.test/3']]
        demo.enrich_sources(sources,'policy history',2)
        self.assertEqual(self.article_download.call_count,2)
        self.assertEqual(sources[0]['evidenceType'],'search_excerpt')
        self.assertEqual(sources[1]['evidenceType'],'article_passages')
        self.assertIn('Earlier policy',sources[1]['excerpt'])
        self.assertEqual(sources[3]['evidenceType'],'search_excerpt')

    def test_publisher_failure_preserves_excerpt_without_retry(self):
        sources=[{'url':'https://news.test/a','excerpt':'Original evidence','evidenceType':'search_excerpt'}]
        demo.enrich_sources(sources,'history',1)
        self.assertEqual(sources[0]['excerpt'],'Original evidence')
        self.assertEqual(sources[0]['evidenceType'],'search_excerpt')
        self.article_download.assert_called_once()

    def test_passages_are_bounded_verbatim_and_in_original_order(self):
        body='Opening date and context.\nUnrelated sports.\nIn 2023 the law changed.\nOfficials denied the allegation.'
        result=demo.article_passages(body,'law',100)
        self.assertLessEqual(len(result),100)
        self.assertTrue(result.startswith('Opening date and context.'))
        self.assertIn('In 2023 the law changed.',result)
        self.assertEqual(result,'\n'.join(p for p in body.splitlines() if p in result))
        self.assertEqual(len(demo.article_passages('x'*6000,'history')),3000)

    def test_expiry_blocks_public_article_connections(self):
        self.now_mock.return_value=self.now+timedelta(days=1)
        with self.assertRaises(demo.DemoError):
            demo.enrich_sources([{'url':'https://news.test/a'}],'history',1)
        self.article_download.assert_not_called()

    @patch('news_demo.ask_model',return_value={'topic':'Jantar Mantar','clarification':'Which protest?'})
    @patch('news_demo.retrieve',return_value=[])
    def test_ambiguity_asks_clarification_without_second_search(self, retrieve, model):
        result=demo.explain('Jantar Mantar today?',None)
        self.assertEqual(result['clarification'],'Which protest?')
        self.assertEqual(retrieve.call_count,1)

    @patch('news_demo.ask_model',return_value={'topic':'CEC protest','eventIdentified':True,
        'clarification':'Why did people demand resignation?','backgroundQuery':'voter roll dispute origins'})
    @patch('news_demo.retrieve',return_value=[])
    def test_identified_event_researches_why_instead_of_asking_user(self, retrieve, model):
        result=demo.explain('Why did people demand Gyanesh Kumar resign?',None)
        self.assertIsNone(result['clarification'])
        self.assertEqual(retrieve.call_count,2)
        self.assertIn('YOUR research task',model.call_args.args[0])

    @patch('news_demo.authenticate',return_value='user')
    @patch('news_demo.explain',return_value={'topic':'Iran','sections':[],'sources':[]})
    def test_same_post_does_not_repeat_provider_work(self, explain, auth):
        request={'question':'Iran news','requestId':'a'*32}
        one,status=demo.handle_question('Bearer token',request)
        two,status=demo.handle_question('Bearer token',request)
        self.assertEqual(one,two)
        explain.assert_called_once()

    @patch('news_demo.authenticate',return_value='user')
    @patch('news_demo.explain',side_effect=RuntimeError('provider-secret'))
    def test_failed_requests_are_counted_and_not_replayed(self, explain, auth):
        request={'question':'Iran news','requestId':'b'*32}
        for i in range(2):
            with self.assertRaises(demo.DemoError) as error:
                demo.handle_question('Bearer token',request)
            self.assertNotIn('provider-secret',str(error.exception))
        explain.assert_called_once()
        self.assertEqual(demo.demo_status()['remaining'],99)

    def test_busy_and_invalid_context_do_not_consume_questions(self):
        store=demo.DemoStore()
        with self.assertRaises(demo.DemoError):
            store.reserve('a','a'*32,'why','b'*32)
        for i in range(demo.MAX_IN_FLIGHT):
            store.reserve('a',f'{i:032x}','Iran',None)
        with self.assertRaises(demo.DemoError) as error:
            store.reserve('b','f'*32,'Iran',None)
        self.assertEqual(error.exception.code,'busy')
        self.assertEqual(demo.demo_status()['remaining'],99)

    def test_cooldown_does_not_consume_another_attempt(self):
        store=demo.DemoStore()
        store.reserve('a','a'*32,'Iran',None)
        store.finish('a'*32,{'topic':'Iran'})
        with self.assertRaises(demo.DemoError) as error:
            store.reserve('a','b'*32,'Why?','a'*32)
        self.assertEqual(error.exception.code,'busy')
        self.assertEqual(demo.demo_status()['remaining'],99)
        self.assertEqual(store.reserve('a','a'*32,'Iran',None)['existing']['status'],'done')
        self.now_mock.return_value=self.now+timedelta(seconds=61)
        self.assertEqual(store.reserve('a','b'*32,'Why?','a'*32)['remaining'],98)
