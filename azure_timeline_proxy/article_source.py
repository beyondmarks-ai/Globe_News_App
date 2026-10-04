"""Read ordinary public article HTML without bypassing publisher restrictions.

Connections are pinned to a validated public IP (including every redirect),
while HTTPS still checks the original hostname. No proxy or credential forwarding.
"""
import ipaddress
import json
import socket
import time
from urllib.parse import urljoin, urlsplit

import urllib3
from bs4 import BeautifulSoup


class UnsafeArticleUrl(ValueError):
    pass


def public_target(url):
    parsed = urlsplit(url)
    if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password:
        raise UnsafeArticleUrl('Not a public article URL')
    port = parsed.port or (443 if parsed.scheme == 'https' else 80)
    if port not in (80, 443):
        raise UnsafeArticleUrl('Unsupported article port')
    addresses = socket.getaddrinfo(parsed.hostname, port, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
        raise UnsafeArticleUrl('Not a public article address')
    return parsed, port, addresses[0][4][0]


def download_html(url):
    deadline = time.monotonic() + 12
    for _ in range(3):
        parsed, port, address = public_target(url)
        if time.monotonic() >= deadline:
            raise TimeoutError('Article download timed out')
        options = dict(port=port, timeout=urllib3.Timeout(connect=3, read=5), retries=False)
        if parsed.scheme == 'https':
            pool = urllib3.HTTPSConnectionPool(address, assert_hostname=parsed.hostname,
                server_hostname=parsed.hostname, cert_reqs='CERT_REQUIRED', **options)
        else:
            pool = urllib3.HTTPConnectionPool(address, **options)
        response = None
        try:
            path = parsed.path or '/'
            if parsed.query:
                path += '?' + parsed.query
            response = pool.request('GET', path, redirect=False, preload_content=False,
                headers={'Host': parsed.netloc, 'User-Agent': 'GlobeNews/1.1 (public article reader)',
                         'Accept': 'text/html,application/xhtml+xml'})
            if response.status in (301, 302, 303, 307, 308):
                url = urljoin(url, response.headers.get('Location', ''))
                continue
            if response.status != 200 or 'html' not in response.headers.get('Content-Type', '').lower():
                raise ValueError('Publisher did not provide readable HTML')
            chunks, size = [], 0
            for chunk in response.stream(16384):
                size += len(chunk)
                if size > 2_000_000 or time.monotonic() >= deadline:
                    raise ValueError('Article exceeded download limits')
                chunks.append(chunk)
            return b''.join(chunks)
        finally:
            if response is not None:
                response.close()
            pool.close()
    raise ValueError('Too many article redirects')


def extract_public_article(html):
    soup = BeautifulSoup(html, 'html.parser')
    def walk(value):
        if isinstance(value, dict):
            yield value
            for child in value.values():
                yield from walk(child)
        elif isinstance(value, list):
            for child in value:
                yield from walk(child)
    data = {}
    for script in soup.select('script[type="application/ld+json"]'):
        try:
            for item in walk(json.loads(script.get_text())):
                kind = item.get('@type', [])
                if isinstance(kind, str):
                    kind = [kind]
                if any(k in kind for k in ('NewsArticle', 'Article', 'ReportageNewsArticle')) and item.get('articleBody'):
                    data = item
                    break
        except (ValueError, TypeError):
            continue
        if data:
            break
    title = str(data.get('headline') or (soup.h1.get_text(' ', strip=True) if soup.h1 else ''))[:300]
    body = data.get('articleBody')
    if not isinstance(body, str):
        node = soup.select_one('[itemprop="articleBody"], article, .article-body, .story-body')
        if node:
            for unwanted in node.select('script, style, nav, aside, footer, form'):
                unwanted.decompose()
            body = '\n'.join(p.get_text(' ', strip=True) for p in node.select('p'))
    if not title or not isinstance(body, str) or len(body.strip()) < 200:
        raise ValueError('Publisher supplied no readable article body')
    image = soup.find('meta', attrs={'property': 'og:image'})
    image_url = image.get('content') if image else None
    if not isinstance(image_url, str) or urlsplit(image_url).scheme not in ('https', 'http'):
        image_url = None
    return title, body.strip()[:14000], image_url
