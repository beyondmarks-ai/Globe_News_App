"""Any-time topic search over retained timeline snapshots, with no paid search tier.

The archive is an FTS5 SQLite blob. Only the background indexer writes it;
interactive queries download at most one bounded archive and never scan blobs.
Dates are observation dates, not invented publication dates.
"""
from __future__ import annotations

import base64
import hashlib
import json
import logging
import re
import sqlite3
import threading
import time
import unicodedata
from datetime import datetime, timezone
from urllib.parse import unquote, urlsplit, urlunsplit, parse_qsl, urlencode

from azure.core.exceptions import ResourceNotFoundError, ResourceExistsError
from azure.storage.blob import ContentSettings
from service_clients import blob_service

CONTAINER = 'timeline-news-cache'
ARCHIVE = 'topic-search/archive-v1.sqlite3'
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
PAGE_SIZE = 20
_lock = threading.Lock()
_cached = None
_checked_at = 0.0
_etag = None
_STOP = set('a an the in on at of to for from and or about news show me all tell what whats is are was were happening latest please give with regarding update updates'.split())
_RELATED = {
    'war': ('war', 'conflict', 'attack', 'strike', 'missile', 'ceasefire'),
    'iran': ('iran', 'iranian'),
    'israel': ('israel', 'israeli'),
    'ukraine': ('ukraine', 'ukrainian'),
    'russia': ('russia', 'russian'),
}


class InvalidSearch(ValueError):
    pass


class ArchiveChanged(Exception):
    pass


def query_terms(query):
    if not isinstance(query, str) or not 2 <= len(query.strip()) <= 200:
        raise InvalidSearch('Enter a topic between 2 and 200 characters.')
    words = re.findall(r'[^\W_]+', unicodedata.normalize('NFKC', query).lower())
    terms = list(dict.fromkeys(w for w in words if w not in _STOP and len(w) > 1))
    if not terms or len(terms) > 12:
        raise InvalidSearch('Enter a specific topic using up to 12 keywords.')
    # Only generated, quoted tokens reach MATCH; raw search syntax never does.
    expression = ' AND '.join('(' + ' OR '.join('"' + s + '"' for s in _RELATED.get(w, (w,))) + ')' for w in terms)
    return terms, expression


def create_archive():
    db = sqlite3.connect(':memory:', check_same_thread=False)
    db.row_factory = sqlite3.Row
    db.executescript('''
        CREATE TABLE stories(id INTEGER PRIMARY KEY, url TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL, source TEXT NOT NULL, places TEXT NOT NULL,
            first_seen TEXT NOT NULL, last_seen TEXT NOT NULL,
            lat REAL, lon REAL, title_inferred INTEGER NOT NULL);
        CREATE INDEX story_date ON stories(first_seen DESC, id);
        CREATE VIRTUAL TABLE terms USING fts5(title, url_words, places, tokenize='porter unicode61');
        CREATE TABLE snapshots(name TEXT PRIMARY KEY, etag TEXT NOT NULL);
        CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    ''')
    return db


def _metadata(db):
    return dict(db.execute('SELECT key,value FROM metadata').fetchall())


def _set_meta(db, key, value):
    db.execute('INSERT OR REPLACE INTO metadata VALUES (?,?)', (key, str(value)))


def canonical_url(value):
    try:
        parts = urlsplit(str(value or '').strip())
        if parts.scheme not in ('http', 'https') or not parts.hostname or parts.username or parts.password:
            return None
        if len(value) > 4096:
            return None
        query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
                 if not k.lower().startswith('utm_') and k.lower() not in ('fbclid', 'gclid')]
        return urlunsplit((parts.scheme, parts.netloc.lower(), parts.path, urlencode(query), ''))
    except (ValueError, TypeError):
        return None


def ingest_snapshot(db, payload, observed_at):
    records = json.loads(payload)
    if isinstance(records, dict):
        records = next((records[k] for k in ('items', 'data', 'news', 'results') if isinstance(records.get(k), list)), [])
    if not isinstance(records, list):
        raise ValueError('Invalid snapshot')
    flattened = []
    for record in records[:1000]:
        if isinstance(record, dict) and isinstance(record.get('data'), list):
            flattened.extend(record['data'])
        else:
            flattened.append(record)
    for record in flattened[:1000]:
        if not isinstance(record, dict):
            continue
        url = canonical_url(record.get('url'))
        if not url:
            continue
        words = re.sub(r'[^\w\s]', ' ', unquote(urlsplit(url).path))[:2000]
        title = ' '.join(str(record.get('headline') or record.get('title') or '').split())[:400]
        inferred = not bool(title)
        title = title or (' '.join(words.split())[:200] or 'Article from ' + urlsplit(url).hostname)
        source = str(record.get('source') or urlsplit(url).hostname)[:200]
        place = str(record.get('place') or '')[:500]
        existing = db.execute('SELECT * FROM stories WHERE url=?', (url,)).fetchone()
        first, last = observed_at, observed_at
        if existing:
            first, last = min(first, existing['first_seen']), max(last, existing['last_seen'])
            place = ' | '.join(dict.fromkeys(existing['places'].split(' | ') + [place]))[:4000]
            if not existing['title_inferred'] and inferred:
                title, inferred = existing['title'], False
        lat, lon = record.get('lat'), record.get('lon')
        try:
            lat, lon = float(lat), float(lon)
            if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                lat, lon = None, None
        except (ValueError, TypeError):
            lat, lon = None, None
        db.execute('''INSERT INTO stories(url,title,source,places,first_seen,last_seen,lat,lon,title_inferred)
            VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(url) DO UPDATE SET
            title=excluded.title,places=excluded.places,first_seen=excluded.first_seen,
            last_seen=excluded.last_seen,title_inferred=excluded.title_inferred''',
            (url, title, source, place, first, last, lat, lon, int(inferred)))
        row_id = db.execute('SELECT id FROM stories WHERE url=?', (url,)).fetchone()[0]
        db.execute('DELETE FROM terms WHERE rowid=?', (row_id,))
        db.execute('INSERT INTO terms(rowid,title,url_words,places) VALUES (?,?,?,?)', (row_id, title, words, place))


def search_archive(db, query, sort='relevance', cursor=None):
    terms, expression = query_terms(query)
    if sort not in ('relevance', 'newest'):
        raise InvalidSearch('Choose relevance or newest.')
    meta = _metadata(db)
    version = meta.get('version', 'initial')
    fingerprint = hashlib.sha256((expression + sort).encode()).hexdigest()[:20]
    offset = 0
    if cursor:
        try:
            if len(cursor) > 512:
                raise ValueError()
            state = json.loads(base64.urlsafe_b64decode(cursor))
            offset = state['offset']
            if state['query'] != fingerprint or type(offset) is not int or not 0 <= offset <= 10000:
                raise ValueError()
            if state['version'] != version:
                raise ArchiveChanged()
        except (ValueError, KeyError, TypeError):
            raise InvalidSearch('Invalid search page. Start a new search.') from None
    order = 'bm25(terms, 6.0, 2.0, 0.2), s.first_seen DESC, s.id' if sort == 'relevance' else 's.first_seen DESC, s.id'
    rows = db.execute(f'''SELECT s.* FROM terms JOIN stories s ON s.id=terms.rowid
        WHERE terms MATCH ? ORDER BY {order} LIMIT ? OFFSET ?''', (expression, PAGE_SIZE + 1, offset)).fetchall()
    count = db.execute('SELECT count(*) FROM terms WHERE terms MATCH ?', (expression,)).fetchone()[0]
    bounds = db.execute('SELECT min(first_seen),max(last_seen),count(*) FROM stories').fetchone()
    next_cursor = None
    if len(rows) > PAGE_SIZE and offset + PAGE_SIZE <= 10000:
        next_cursor = base64.urlsafe_b64encode(json.dumps({'version': version, 'query': fingerprint, 'offset': offset + PAGE_SIZE}).encode()).decode()
    return {
        'query': query.strip(), 'keywords': terms, 'sort': sort, 'total': count,
        'items': [{'id': 'archive-' + str(r['id']), 'headline': r['title'],
                   'url': r['url'], 'source': r['source'], 'place': r['places'],
                   'firstSeen': r['first_seen'], 'lastSeen': r['last_seen'],
                   'lat': r['lat'], 'lon': r['lon'], 'titleInferred': bool(r['title_inferred'])}
                  for r in rows[:PAGE_SIZE]],
        'nextCursor': next_cursor,
        'coverage': {'from': bounds[0], 'to': bounds[1], 'articles': bounds[2],
            'updatedAt': meta.get('updatedAt'), 'backfillComplete': meta.get('backfillComplete') == 'true',
            'description': 'Any time in our saved news archive. Searches headlines, URL keywords and locations, not every publisher or full article text. Dates show when we observed a story, not its publication date.'},
    }


def search(query, sort='relevance', cursor=None):
    global _cached, _checked_at, _etag
    query_terms(query)
    with _lock:
        if _cached is None or time.monotonic() - _checked_at > 60:
            blob = blob_service().get_blob_client(CONTAINER, ARCHIVE)
            properties = blob.get_blob_properties()
            if properties.size > MAX_ARCHIVE_BYTES:
                raise RuntimeError('Archive exceeds configured capacity')
            if _cached is None or properties.etag != _etag:
                data = blob.download_blob().readall()
                db = sqlite3.connect(':memory:', check_same_thread=False)
                try:
                    db.deserialize(data)
                    db.row_factory = sqlite3.Row
                    db.execute('PRAGMA query_only=ON')
                    _metadata(db)
                except Exception:
                    db.close()
                    raise
                if _cached is not None:
                    _cached.close()
                _cached, _etag = db, properties.etag
            _checked_at = time.monotonic()
        return search_archive(_cached, query, sort, cursor)


def update_archive(max_snapshots=96, max_seconds=90):
    """Resumable backfill; a renewable blob lease prevents competing publishers."""
    container = blob_service().get_container_client(CONTAINER)
    lock_blob = container.get_blob_client('topic-search/indexer.lock')
    try:
        lock_blob.upload_blob(b'', overwrite=False)
    except ResourceExistsError:
        pass
    lease = lock_blob.acquire_lease(lease_duration=60)
    db = None
    start = time.monotonic()
    renewed = start
    processed = 0
    try:
        target = container.get_blob_client(ARCHIVE)
        try:
            if target.get_blob_properties().size > MAX_ARCHIVE_BYTES:
                raise RuntimeError('Archive exceeds configured capacity')
            data = target.download_blob().readall()
            db = sqlite3.connect(':memory:')
            db.deserialize(data)
            db.row_factory = sqlite3.Row
        except ResourceNotFoundError:
            db = create_archive()
        meta = _metadata(db)
        pages = container.list_blobs(name_starts_with='20', results_per_page=max_snapshots).by_page(
            continuation_token=meta.get('continuation') or None)
        page = next(pages, [])
        completed_page = True
        for blob in page:
            if time.monotonic() - start > max_seconds:
                completed_page = False
                break
            if time.monotonic() - renewed > 20:
                lease.renew()
                renewed = time.monotonic()
            if not re.fullmatch(r'\d{4}/\d{2}/\d{2}/\d{2}-\d{2}\.json', blob.name):
                continue
            old = db.execute('SELECT etag FROM snapshots WHERE name=?', (blob.name,)).fetchone()
            if old and old[0] == str(blob.etag):
                continue
            if blob.size > 4 * 1024 * 1024:
                logging.warning('Skipping oversized timeline snapshot')
                continue
            observed = datetime.strptime(blob.name, '%Y/%m/%d/%H-%M.json').replace(tzinfo=timezone.utc).isoformat()
            payload = container.get_blob_client(blob.name).download_blob().readall()
            ingest_snapshot(db, payload, observed)
            db.execute('INSERT OR REPLACE INTO snapshots VALUES (?,?)', (blob.name, str(blob.etag)))
            processed += 1
        if completed_page:
            _set_meta(db, 'continuation', pages.continuation_token or '')
            if not pages.continuation_token:
                _set_meta(db, 'backfillComplete', 'true')
        # Always include the newest successfully cached feed during historical backfill.
        try:
            latest = container.get_blob_client('latest.json')
            props = latest.get_blob_properties()
            if props.size <= 4 * 1024 * 1024:
                ingest_snapshot(db, latest.download_blob().readall(), props.last_modified.isoformat())
        except ResourceNotFoundError:
            pass
        now = datetime.now(timezone.utc).isoformat()
        _set_meta(db, 'updatedAt', now)
        _set_meta(db, 'version', now)
        db.commit()
        data = db.serialize()
        if len(data) > MAX_ARCHIVE_BYTES:
            raise RuntimeError('Archive exceeds configured capacity')
        lease.renew()
        target.upload_blob(data, overwrite=True, content_settings=ContentSettings(content_type='application/vnd.sqlite3'))
        return {'processed': processed, 'articles': db.execute('SELECT count(*) FROM stories').fetchone()[0],
                'bytes': len(data), 'backfillComplete': _metadata(db).get('backfillComplete') == 'true'}
    finally:
        if db is not None:
            db.close()
        lease.release()
