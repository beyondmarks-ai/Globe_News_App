from __future__ import annotations

import hashlib
import json
import os
from urllib.parse import urlparse

import requests
from azure.core.exceptions import ResourceNotFoundError
from azure.storage.blob import BlobServiceClient, ContentSettings

_LANGUAGE_NAMES = {
    "en-US": "English",
    "kn-IN": "Kannada",
    "hi-IN": "Hindi",
    "ur-PK": "Urdu",
}


def _source_headline(story: dict) -> str:
    return str(
        story.get("headline")
        or story.get("title")
        or story.get("headlineEnglish")
        or story.get("headlineKannada")
        or ""
    ).strip()[:300]


def notification_headline(story: dict, language: str) -> str:
    original = _source_headline(story)
    if not original:
        place = str(story.get("place") or story.get("country") or "your area")
        return f"News update from {place}"[:90]
    cache = _cache_blob(story, language)
    try:
        payload = json.loads(cache.download_blob().readall())
        value = str(payload.get("headline") or "").strip()
        if value:
            return value[:90]
    except ResourceNotFoundError:
        pass
    except Exception:
        pass
    refined = _refine(original, story, language)
    try:
        cache.upload_blob(
            json.dumps({"headline": refined}, ensure_ascii=False),
            overwrite=True,
            content_settings=ContentSettings(content_type="application/json"),
        )
    except Exception:
        pass
    return refined


def _cache_blob(story: dict, language: str):
    service = BlobServiceClient.from_connection_string(
        os.environ["AzureWebJobsStorage"]
    )
    container = service.get_container_client("notification-headlines")
    try:
        container.create_container()
    except Exception:
        pass
    basis = f"{story.get('id')}|{story.get('url')}|{language}"
    key = hashlib.sha256(basis.encode("utf-8")).hexdigest()
    return container.get_blob_client(f"{language}/{key}.json")


def _refine(original: str, story: dict, language: str) -> str:
    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT", "").rstrip("/")
    api_key = os.environ.get("AZURE_OPENAI_KEY", "")
    deployment = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT", "")
    if not endpoint or not api_key or not deployment:
        return original[:90]
    language_name = _LANGUAGE_NAMES.get(language, "English")
    response = requests.post(
        f"{endpoint}/openai/v1/chat/completions",
        headers={"api-key": api_key, "Content-Type": "application/json"},
        json={
            "model": deployment,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "Rewrite a news headline using only supplied facts. "
                        "Never add names, numbers, places, causes, or claims. "
                        "Be neutral, clear, and under 65 characters."
                    ),
                },
                {
                    "role": "user",
                    "content": json.dumps(
                        {
                            "language": language_name,
                            "headline": original,
                            "place": story.get("place"),
                            "country": story.get("country"),
                            "source": story.get("source"),
                        },
                        ensure_ascii=False,
                    ),
                },
            ],
            "temperature": 0.1,
            "max_tokens": 100,
        },
        timeout=(5, 20),
    )
    response.raise_for_status()
    value = response.json()["choices"][0]["message"]["content"].strip()
    value = value.strip('"').splitlines()[0].strip()
    return (value or original)[:90]
