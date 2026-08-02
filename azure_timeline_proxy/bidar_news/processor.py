from __future__ import annotations

import dataclasses
import json
import logging
import os
import re

import requests

from .ai import create_embedding, structure_article
from .extractor import download_html, extract_article
from .geocoder import verified_location
from .repository import CityNewsRepository


def _firecrawl_fallback(url: str) -> str | None:
    key = os.environ.get("FIRECRAWL_API_KEY")
    if not key:
        return None
    response = requests.post(
        "https://api.firecrawl.dev/v2/scrape",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json={
            "url": url,
            "formats": ["markdown"],
            "onlyMainContent": True,
            "blockAds": True,
            "removeBase64Images": True,
            "timeout": 60_000,
        },
        timeout=(10, 75),
    )
    response.raise_for_status()
    data = response.json().get("data", {})
    markdown = data.get("markdown")
    return markdown if isinstance(markdown, str) else None


def _tone_color(tone: float) -> str:
    if tone <= -1:
        return "red"
    if tone >= 1:
        return "green"
    return "yellow"


def process_message(message: dict, repository: CityNewsRepository | None = None) -> str:
    article_id = str(message.get("sourceArticleId", "")).strip()
    url = str(message.get("canonicalUrl", "")).strip()
    if not article_id or not re.fullmatch(r"\d+", article_id) or not url:
        raise ValueError("Invalid article queue message")

    response = download_html(url)
    response.raise_for_status()
    try:
        article = extract_article(response.text, url)
    except ValueError:
        fallback = _firecrawl_fallback(url)
        article = extract_article(response.text, url, fallback_body=fallback)

    repository = repository or CityNewsRepository()
    item_id = f"vk:{article.sourceArticleId}"
    existing = repository.get(item_id)
    if existing and existing.get("contentHash") == article.contentHash:
        if existing.get("hasEmbedding") and existing.get("embedding"):
            return "unchanged"
        try:
            embedding = create_embedding(article, existing)
        except (requests.RequestException, TypeError, ValueError) as error:
            logging.warning("Bidar embedding backfill failed: %s", type(error).__name__)
            return "unchanged"
        existing["embedding"] = embedding
        existing["hasEmbedding"] = bool(embedding)
        repository.upsert(existing)
        return "embedding_backfilled"

    structured = structure_article(article)
    try:
        embedding = create_embedding(article, structured)
    except (requests.RequestException, TypeError, ValueError) as error:
        logging.warning("Bidar embedding failed: %s", type(error).__name__)
        embedding = []
    location = verified_location(structured)
    tone = structured["tone"]
    document = {
        "id": item_id,
        "documentType": "article",
        "clusterId": f"bidar-vk-{article.sourceArticleId}",
        "source": "Vijaya Karnataka",
        **dataclasses.asdict(article),
        **structured,
        "primaryLocation": location,
        "mapVisible": location is not None,
        "color": _tone_color(tone),
        "embedding": embedding,
        "hasEmbedding": bool(embedding),
        "aiReady": True,
        "pulseStrength": 1.0,
        "sources": [
            {
                "name": "Vijaya Karnataka",
                "url": article.canonicalUrl,
                "sourceArticleId": article.sourceArticleId,
            }
        ],
    }
    repository.upsert(document)
    return "created" if existing is None else "updated"


def decode_message(body: bytes | str) -> dict:
    if isinstance(body, bytes):
        body = body.decode("utf-8")
    value = json.loads(body)
    if not isinstance(value, dict):
        raise ValueError("Queue message is not an object")
    return value
