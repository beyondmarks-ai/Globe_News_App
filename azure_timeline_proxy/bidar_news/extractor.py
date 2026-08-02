from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict, dataclass
from typing import Any
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

from .config import VK_CATEGORY_URL, VK_USER_AGENT


_ARTICLE_ID = re.compile(r"/articleshow/(\d+)\.cms(?:[?#]|$)", re.IGNORECASE)


@dataclass(frozen=True)
class DiscoveredArticle:
    sourceArticleId: str
    canonicalUrl: str

    def as_message(self) -> dict[str, str]:
        return asdict(self)


@dataclass(frozen=True)
class ExtractedArticle:
    sourceArticleId: str
    canonicalUrl: str
    headline: str
    articleBody: str
    description: str
    imageUrl: str | None
    author: str | None
    datePublished: str | None
    dateModified: str | None
    category: str
    language: str
    contentHash: str


def request_headers() -> dict[str, str]:
    return {
        "User-Agent": VK_USER_AGENT,
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "kn-IN,kn;q=0.9,en;q=0.5",
    }


def canonical_article_url(url: str) -> DiscoveredArticle | None:
    absolute = urljoin(VK_CATEGORY_URL, url)
    parsed = urlparse(absolute)
    if parsed.hostname not in {"vijaykarnataka.com", "www.vijaykarnataka.com"}:
        return None
    match = _ARTICLE_ID.search(parsed.path)
    if not match:
        return None
    canonical = f"https://vijaykarnataka.com{parsed.path}"
    return DiscoveredArticle(match.group(1), canonical)


def discover_articles(html: str) -> list[DiscoveredArticle]:
    soup = BeautifulSoup(html, "html.parser")
    unique: dict[str, DiscoveredArticle] = {}
    for anchor in soup.select('a[href*="/articleshow/"]'):
        article = canonical_article_url(anchor.get("href", ""))
        if article:
            unique.setdefault(article.sourceArticleId, article)
    return list(unique.values())


def _walk_json(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk_json(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_json(child)


def _news_article_json_ld(soup: BeautifulSoup) -> dict[str, Any]:
    for script in soup.select('script[type="application/ld+json"]'):
        try:
            decoded = json.loads(script.get_text(strip=True))
        except (TypeError, json.JSONDecodeError):
            continue
        for item in _walk_json(decoded):
            kind = item.get("@type")
            kinds = kind if isinstance(kind, list) else [kind]
            if "NewsArticle" in kinds:
                return item
    return {}


def _meta(soup: BeautifulSoup, *names: str) -> str:
    for name in names:
        tag = soup.find("meta", attrs={"property": name})
        if tag is None:
            tag = soup.find("meta", attrs={"name": name})
        if tag and tag.get("content"):
            return str(tag["content"]).strip()
    return ""


def _person_name(value: Any) -> str | None:
    if isinstance(value, list) and value:
        value = value[0]
    if isinstance(value, dict):
        value = value.get("name")
    text = str(value or "").strip()
    return text[:300] or None


def _image_url(value: Any, soup: BeautifulSoup) -> str | None:
    if isinstance(value, list) and value:
        value = value[0]
    if isinstance(value, dict):
        value = value.get("url") or value.get("contentUrl")
    candidate = str(value or _meta(soup, "og:image", "twitter:image")).strip()
    parsed = urlparse(candidate)
    return candidate if parsed.scheme in {"http", "https"} and parsed.hostname else None


def _selector_text(soup: BeautifulSoup, selectors: tuple[str, ...]) -> str:
    for selector in selectors:
        node = soup.select_one(selector)
        if node:
            value = node.get_text(" ", strip=True)
            if value:
                return value
    return ""


def extract_article(
    html: str,
    requested_url: str,
    fallback_body: str | None = None,
) -> ExtractedArticle:
    discovered = canonical_article_url(requested_url)
    if discovered is None:
        raise ValueError("Not a Vijaya Karnataka article URL")
    soup = BeautifulSoup(html, "html.parser")
    data = _news_article_json_ld(soup)

    canonical_tag = soup.find("link", rel="canonical")
    canonical_href = canonical_tag.get("href") if canonical_tag else None
    canonical = str(
        data.get("url") or _meta(soup, "og:url") or canonical_href or requested_url
    ).strip()
    normalized = canonical_article_url(canonical) or discovered
    headline = str(
        data.get("headline")
        or _meta(soup, "og:title", "twitter:title")
        or _selector_text(soup, ("h1", ".article-title"))
    ).strip()
    body = str(
        data.get("articleBody")
        or _selector_text(
            soup,
            (
                "[itemprop='articleBody']",
                ".article_content",
                ".article-body",
                ".story-content",
            ),
        )
        or fallback_body
        or ""
    ).strip()
    description = str(
        data.get("description") or _meta(soup, "og:description", "description")
    ).strip()
    if not headline or len(body) < 120:
        raise ValueError("Article metadata is incomplete")

    fingerprint = hashlib.sha256(
        "\n".join((headline, body, str(data.get("dateModified") or ""))).encode("utf-8")
    ).hexdigest()
    return ExtractedArticle(
        sourceArticleId=normalized.sourceArticleId,
        canonicalUrl=normalized.canonicalUrl,
        headline=headline[:500],
        articleBody=body[:100_000],
        description=description[:4_000],
        imageUrl=_image_url(data.get("image"), soup),
        author=_person_name(data.get("author")),
        datePublished=str(data.get("datePublished") or "").strip() or None,
        dateModified=str(data.get("dateModified") or "").strip() or None,
        category="Bidar",
        language="kn-IN",
        contentHash=fingerprint,
    )


def download_html(url: str, conditional: dict[str, str] | None = None):
    headers = request_headers()
    headers.update(conditional or {})
    response = requests.get(url, headers=headers, timeout=(10, 40))
    # The source uses UTF-8 Kannada but may omit the charset. Requests would
    # otherwise default to ISO-8859-1 and corrupt the source text.
    if response.status_code != 304:
        response.encoding = "utf-8"
    return response
