from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone

from azure.servicebus import ServiceBusClient, ServiceBusMessage

from .config import (
    FULL_REFRESH_SECONDS,
    MAX_CATEGORY_ARTICLES,
    SERVICE_BUS_QUEUE,
    VK_CATEGORY_URL,
)
from .extractor import discover_articles, download_html
from .state import DiscoveryStateStore


def _parse_time(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def run_discovery() -> dict:
    state_store = DiscoveryStateStore(os.environ["AzureWebJobsStorage"])
    state = state_store.load()
    conditional = {}
    if state.get("etag"):
        conditional["If-None-Match"] = str(state["etag"])
    if state.get("lastModified"):
        conditional["If-Modified-Since"] = str(state["lastModified"])

    response = download_html(VK_CATEGORY_URL, conditional)
    now = datetime.now(timezone.utc)
    if response.status_code == 304:
        state["lastCheckedAt"] = now.isoformat()
        state_store.save(state)
        return {"status": "not_modified", "queued": 0}
    response.raise_for_status()

    content_hash = hashlib.sha256(response.content).hexdigest()
    articles = discover_articles(response.text)[:MAX_CATEGORY_ARTICLES]
    if not articles:
        raise ValueError("No Vijaya Karnataka Bidar article links discovered")

    old_ids = set(state.get("articleIds", []))
    new_articles = [item for item in articles if item.sourceArticleId not in old_ids]
    last_full = _parse_time(state.get("lastFullRefreshAt"))
    full_refresh_due = (
        last_full is None or (now - last_full).total_seconds() >= FULL_REFRESH_SECONDS
    )
    content_changed = content_hash != state.get("contentHash")

    # New IDs are immediate. Existing visible IDs are revisited every six hours
    # so edits are detected without repeatedly downloading every article.
    queued = articles if full_refresh_due else new_articles
    if queued:
        connection = os.environ["BIDAR_SERVICE_BUS_CONNECTION"]
        with ServiceBusClient.from_connection_string(connection) as client:
            with client.get_queue_sender(queue_name=SERVICE_BUS_QUEUE) as sender:
                messages = [
                    ServiceBusMessage(
                        json.dumps(item.as_message(), separators=(",", ":")),
                        content_type="application/json",
                        message_id=f"vk-{item.sourceArticleId}-{content_hash[:12]}",
                    )
                    for item in queued
                ]
                sender.send_messages(messages)

    state.update(
        {
            "etag": response.headers.get("ETag"),
            "lastModified": response.headers.get("Last-Modified"),
            "contentHash": content_hash,
            "articleIds": [item.sourceArticleId for item in articles],
            "lastCheckedAt": now.isoformat(),
        }
    )
    if full_refresh_due:
        state["lastFullRefreshAt"] = now.isoformat()
    state_store.save(state)
    return {
        "status": "changed" if content_changed else "unchanged",
        "discovered": len(articles),
        "new": len(new_articles),
        "queued": len(queued),
        "fullRefresh": full_refresh_due,
    }
