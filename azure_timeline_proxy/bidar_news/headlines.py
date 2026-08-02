from __future__ import annotations

import logging

import requests


def attach_indexed_headlines(records, endpoint, index_name, api_key, batch_size=100):
    if not endpoint or not index_name or not api_key:
        return records
    urls = _unique_urls(records)
    titles = {}
    search_url = endpoint.rstrip('/')
    search_url += '/indexes/' + index_name + '/docs/search'
    search_url += '?api-version=2024-07-01'
    for start in range(0, len(urls), batch_size):
        _load_title_batch(
            search_url,
            api_key,
            urls[start : start + batch_size],
            titles,
        )
    if not titles:
        return records
    enriched = []
    for record in records:
        copy = dict(record)
        title = titles.get(str(copy.get('url') or '').strip())
        existing = _clean_title(copy.get('headline') or copy.get('title'))
        if title and not existing:
            copy['headline'] = title
        enriched.append(copy)
    return enriched


def _unique_urls(records):
    seen = set()
    result = []
    for record in records:
        url = str(record.get('url') or '').strip()
        if url.startswith(('https://', 'http://')) and url not in seen:
            seen.add(url)
            result.append(url)
    return result


def _load_title_batch(search_url, api_key, urls, titles):
    quote = chr(39)
    escaped = [
        value.replace(quote, quote + quote) for value in urls if '~' not in value
    ]
    if not escaped:
        return
    payload = dict()
    payload['search'] = '*'
    delimiter = '~'
    values = delimiter.join(escaped)
    expression = 'search.in(url, ' + quote + values + quote
    expression = expression + ', ' + quote + delimiter + quote + ')'
    payload['filter'] = expression
    payload['select'] = 'url,title'
    payload['top'] = len(escaped)
    _request_title_batch(search_url, api_key, payload, titles)


def _request_title_batch(search_url, api_key, payload, titles):
    try:
        response = requests.post(
            search_url,
            headers={'api-key': api_key, 'Content-Type': 'application/json'},
            json=payload,
            timeout=(5, 20),
        )
        response.raise_for_status()
        documents = response.json().get('value', [])
        if not isinstance(documents, list):
            return
        for document in documents:
            if not isinstance(document, dict):
                continue
            url = str(document.get('url') or '').strip()
            title = _clean_title(document.get('title'))
            if url and title:
                titles[url] = title
    except (requests.RequestException, ValueError, TypeError):
        logging.warning('Azure Search headline batch lookup failed', exc_info=True)


def _clean_title(value):
    title = ' '.join(str(value or '').split()).strip()[:400]
    rejected = (
        'error:',
        'access denied',
        'request could not be satisfied',
        'page not found',
    )
    return '' if not title or title.lower().startswith(rejected) else title
