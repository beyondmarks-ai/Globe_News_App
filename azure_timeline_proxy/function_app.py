import ipaddress
import json
import logging
import os
import socket
from datetime import datetime, timezone
from urllib.parse import urljoin, urlparse

import azure.functions as func
import requests
from azure.core.exceptions import ResourceNotFoundError
from azure.storage.blob import BlobServiceClient, ContentSettings


app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

_UPSTREAM_URL = os.environ.get(
    "TIMELINE_NEWS_UPSTREAM_URL",
    "https://gdelt-live-updater-bqgza4a6b2gqakdc.southeastasia-01.azurewebsites.net/api/timeline_news",
)
_CACHE_CONTAINER = "timeline-news-cache"
_ARTICLE_LANGUAGES = {
    "en-US": "English",
    "kn-IN": "Kannada",
    "hi-IN": "Hindi",
    "ur-PK": "Urdu",
}
_MAX_ARTICLE_BYTES = 2_000_000


def _response(body: bytes | str, status: int, cache_status: str) -> func.HttpResponse:
    return func.HttpResponse(
        body=body,
        status_code=status,
        mimetype="application/json",
        headers={
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=300, stale-if-error=86400",
            "X-Timeline-Cache": cache_status,
        },
    )


def _article_response(payload: dict, status: int) -> func.HttpResponse:
    return func.HttpResponse(
        body=json.dumps(payload, ensure_ascii=False),
        status_code=status,
        mimetype="application/json",
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Accept, Content-Type",
            "Cache-Control": "no-store",
        },
    )


def _valid_slot(date_value: str | None, time_value: str | None) -> bool:
    if date_value is None or time_value is None:
        return False
    try:
        parsed = datetime.strptime(f"{date_value} {time_value}", "%Y-%m-%d %H:%M")
    except ValueError:
        return False
    return parsed.minute in (0, 15, 30, 45)


def _cache_blob(date_value: str, time_value: str):
    connection_string = os.environ["AzureWebJobsStorage"]
    service = BlobServiceClient.from_connection_string(connection_string)
    container = service.get_container_client(_CACHE_CONTAINER)
    try:
        container.create_container()
    except Exception as error:
        if "ContainerAlreadyExists" not in str(error):
            logging.info("Cache container create skipped: %s", type(error).__name__)
    name = f"{date_value.replace('-', '/')}/{time_value.replace(':', '-')}.json"
    return container.get_blob_client(name)


def _latest_cache_blob():
    connection_string = os.environ["AzureWebJobsStorage"]
    service = BlobServiceClient.from_connection_string(connection_string)
    container = service.get_container_client(_CACHE_CONTAINER)
    try:
        container.create_container()
    except Exception as error:
        if "ContainerAlreadyExists" not in str(error):
            logging.info("Cache container create skipped: %s", type(error).__name__)
    return container.get_blob_client("latest.json")


def _store_latest(payload: bytes) -> None:
    _latest_cache_blob().upload_blob(
        payload,
        overwrite=True,
        content_settings=ContentSettings(content_type="application/json"),
    )


def _normalized_timeline_bytes(payload: bytes) -> bytes:
    decoded = json.loads(payload)
    records = []
    if isinstance(decoded, list):
        for value in decoded:
            candidates = value.get("data") if isinstance(value, dict) else None
            if isinstance(candidates, list):
                records.extend(candidates[: 1000 - len(records)])
            else:
                records.append(value)
            if len(records) >= 1000:
                break
    elif isinstance(decoded, dict):
        for key in ("items", "data", "news", "results"):
            candidates = decoded.get(key)
            if isinstance(candidates, list):
                records.extend(candidates[:1000])
                break
    return json.dumps(records, ensure_ascii=False, separators=(",", ":")).encode(
        "utf-8"
    )


def _validated_public_url(value: object) -> str | None:
    if not isinstance(value, str) or not value.strip():
        return None
    parsed = urlparse(value.strip())
    if parsed.scheme.lower() not in ("http", "https") or not parsed.hostname:
        return None
    try:
        port = parsed.port
    except ValueError:
        return None
    if parsed.username or parsed.password or port not in (None, 80, 443):
        return None
    try:
        addresses = socket.getaddrinfo(parsed.hostname, port or 443)
    except socket.gaierror:
        return None
    for address in addresses:
        ip = ipaddress.ip_address(address[4][0])
        if not ip.is_global:
            return None
    return value.strip()


def _download_article(url: str) -> tuple[str, str, str | None]:
    api_key = os.environ.get("FIRECRAWL_API_KEY", "")
    if not api_key:
        raise RuntimeError("Firecrawl is not configured")
    response = requests.post(
        "https://api.firecrawl.dev/v2/scrape",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "url": url,
            "formats": ["markdown"],
            "onlyMainContent": True,
            "blockAds": True,
            "removeBase64Images": True,
            "maxAge": 900_000,
            "timeout": 60_000,
        },
        timeout=(10, 75),
    )
    response.raise_for_status()
    result = response.json()
    if not isinstance(result, dict) or result.get("success") is False:
        raise ValueError("Firecrawl scrape failed")
    data = result.get("data")
    if not isinstance(data, dict):
        raise ValueError("Firecrawl returned no article data")
    markdown = data.get("markdown")
    if not isinstance(markdown, str) or len(markdown.strip()) < 200:
        raise ValueError("Firecrawl returned too little readable text")
    metadata = data.get("metadata")
    if not isinstance(metadata, dict):
        metadata = {}
    title = str(
        metadata.get("ogTitle")
        or metadata.get("title")
        or metadata.get("twitterTitle")
        or ""
    ).strip()[:300]
    image_url = (
        metadata.get("ogImage")
        or metadata.get("twitterImage")
        or metadata.get("image")
    )
    if not isinstance(image_url, str) or urlparse(image_url).scheme.lower() not in (
        "http",
        "https",
    ):
        image_url = None
    return title, markdown.strip()[:14_000], image_url


def _summarize_article(
    article_url: str,
    language_code: str,
    scraped_title: str,
    article_text: str,
    image_url: str | None,
) -> dict:
    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT", "").rstrip("/")
    api_key = os.environ.get("AZURE_OPENAI_KEY", "")
    deployment = os.environ.get("AZURE_OPENAI_CHAT_DEPLOYMENT", "")
    if not endpoint or not api_key or not deployment:
        raise RuntimeError("Azure OpenAI is not configured")
    language = _ARTICLE_LANGUAGES[language_code]
    prompt = f"""
Return a factual news summary in {language} as one JSON object with exactly
these string fields: title, emoji, whatHappened, when, where, why, how.
Use a short headline, one relevant emoji, and concise neutral explanations.
Do not invent missing facts; say that the article does not specify them.
Original title: {scraped_title}
Original URL: {article_url}
Article text:
{article_text}
""".strip()
    response = requests.post(
        f"{endpoint}/openai/v1/chat/completions",
        headers={"api-key": api_key, "Content-Type": "application/json"},
        json={
            "model": deployment,
            "messages": [
                {
                    "role": "system",
                    "content": "You extract structured facts from news articles.",
                },
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.2,
            "max_tokens": 900,
            "response_format": {"type": "json_object"},
        },
        timeout=(10, 60),
    )
    response.raise_for_status()
    content = response.json()["choices"][0]["message"]["content"].strip()
    if content.startswith("```"):
        content = content.replace("```json", "", 1).replace("```", "").strip()
    parsed = json.loads(content)
    if not isinstance(parsed, dict):
        raise ValueError("AI response is not an object")

    def text(key: str, fallback: str = "") -> str:
        value = parsed.get(key)
        return str(value).strip()[:2_000] if value is not None else fallback

    return {
        "title": text("title", scraped_title),
        "emoji": text("emoji", "\U0001F4F0")[:8],
        "whatHappened": text("whatHappened"),
        "when": text("when"),
        "where": text("where"),
        "why": text("why"),
        "how": text("how"),
        "imageUrl": image_url,
    }


@app.route(route="timeline-news", methods=["GET", "OPTIONS"])
def timeline_news_proxy(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return func.HttpResponse(
            status_code=204,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "Accept, Content-Type",
            },
        )

    date_value = req.params.get("date")
    time_value = req.params.get("time")
    if not _valid_slot(date_value, time_value):
        return _response(
            json.dumps({"error": "date and time must identify a 15-minute UTC slot"}),
            400,
            "BYPASS",
        )

    try:
        blob = _cache_blob(date_value, time_value)
        try:
            cached = blob.download_blob().readall()
            normalized = _normalized_timeline_bytes(cached)
            if normalized != cached:
                blob.upload_blob(
                    normalized,
                    overwrite=True,
                    content_settings=ContentSettings(content_type="application/json"),
                )
            return _response(normalized, 200, "HIT")
        except ResourceNotFoundError:
            pass

        if req.params.get("prefer_cached") == "1":
            try:
                latest = _normalized_timeline_bytes(
                    _latest_cache_blob().download_blob().readall()
                )
                return _response(latest, 200, "FALLBACK")
            except ResourceNotFoundError:
                pass

        function_key = os.environ.get("TIMELINE_NEWS_FUNCTION_KEY", "")
        if not function_key:
            logging.error("TIMELINE_NEWS_FUNCTION_KEY is not configured")
            return _response(json.dumps({"error": "Timeline service is unavailable"}), 503, "MISS")

        upstream = requests.get(
            _UPSTREAM_URL,
            params={"date": date_value, "time": time_value},
            headers={"Accept": "application/json", "x-functions-key": function_key},
            timeout=(10, 180),
        )
        if upstream.status_code < 200 or upstream.status_code >= 300:
            logging.warning("Timeline upstream returned %s", upstream.status_code)
            return _response(
                json.dumps({"error": "Timeline service request failed"}),
                502,
                "MISS",
            )

        normalized = _normalized_timeline_bytes(upstream.content)
        blob.upload_blob(
            normalized,
            overwrite=True,
            content_settings=ContentSettings(content_type="application/json"),
        )
        _store_latest(normalized)
        return _response(normalized, 200, "MISS")
    except requests.Timeout:
        logging.warning("Timeline upstream timed out")
        return _response(json.dumps({"error": "Timeline service timed out"}), 504, "MISS")
    except Exception:
        logging.exception("Timeline proxy request failed")
        return _response(json.dumps({"error": "Timeline service is unavailable"}), 503, "MISS")


@app.timer_trigger(
    schedule="0 3,18,33,48 * * * *",
    arg_name="timer",
    run_on_startup=True,
    use_monitor=True,
)
def preload_latest_timeline(timer: func.TimerRequest) -> None:
    del timer
    now = datetime.now(timezone.utc)
    minute = (now.minute // 15) * 15
    slot = now.replace(minute=minute, second=0, microsecond=0)
    date_value = slot.strftime("%Y-%m-%d")
    time_value = slot.strftime("%H:%M")
    try:
        blob = _cache_blob(date_value, time_value)
        try:
            normalized = _normalized_timeline_bytes(blob.download_blob().readall())
        except ResourceNotFoundError:
            function_key = os.environ.get("TIMELINE_NEWS_FUNCTION_KEY", "")
            if not function_key:
                raise RuntimeError("Timeline function key is not configured")
            upstream = requests.get(
                _UPSTREAM_URL,
                params={"date": date_value, "time": time_value},
                headers={
                    "Accept": "application/json",
                    "x-functions-key": function_key,
                },
                timeout=(10, 180),
            )
            upstream.raise_for_status()
            normalized = _normalized_timeline_bytes(upstream.content)
            blob.upload_blob(
                normalized,
                overwrite=True,
                content_settings=ContentSettings(content_type="application/json"),
            )
        _store_latest(normalized)
        logging.info("Preloaded timeline slot %s %s UTC", date_value, time_value)
    except Exception:
        logging.exception("Timeline preloader failed")


@app.route(route="article-details", methods=["POST", "OPTIONS"])
def article_details(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return _article_response({}, 204)
    try:
        body = req.get_json()
    except ValueError:
        return _article_response({"error": "Invalid request"}, 400)
    if not isinstance(body, dict):
        return _article_response({"error": "Invalid request"}, 400)
    article_url = _validated_public_url(body.get("url"))
    language = body.get("language")
    if article_url is None or language not in _ARTICLE_LANGUAGES:
        return _article_response({"error": "Invalid request"}, 400)
    try:
        title, article_text, image_url = _download_article(article_url)
        result = _summarize_article(
            article_url,
            language,
            title,
            article_text,
            image_url,
        )
        return _article_response(result, 200)
    except requests.Timeout:
        logging.warning("Article enrichment timed out")
        return _article_response({"error": "Article enrichment failed"}, 504)
    except Exception:
        logging.exception("Article enrichment failed")
        return _article_response({"error": "Article enrichment failed"}, 502)
