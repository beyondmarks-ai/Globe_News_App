from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from .headlines import notification_headline
from .models import (
    delivery_allowed,
    is_quiet,
    local_time,
    notification_copy,
    point_matches_alert,
    story_id,
    story_point,
)
from .repository import NewsAlertRepository


def process_timeline_alerts(
    records: list[dict],
    slot: datetime,
    repository: NewsAlertRepository | None = None,
    sender: object | None = None,
) -> dict:
    repository = repository or NewsAlertRepository()
    alerts = repository.active()
    if not alerts:
        return {"alerts": 0, "matched": 0, "sent": 0}
    if sender is None:
        from .fcm import FcmSender

        sender = FcmSender()
    now = datetime.now(timezone.utc)
    matched_count = 0
    sent_count = 0

    for alert in alerts:
        seen = {str(value) for value in alert.get("seenStoryIds", [])}
        pending = [
            value for value in alert.get("pendingItems", []) if isinstance(value, dict)
        ]
        pending_ids = {story_id(value) for value in pending}

        for story in records:
            if not isinstance(story, dict):
                continue
            point = story_point(story)
            if point is None:
                continue
            identifier = story_id(story)
            if identifier in seen or identifier in pending_ids:
                continue
            if not point_matches_alert(alert, point[0], point[1]):
                continue
            pending.append(_notification_item(story, identifier, point))
            pending_ids.add(identifier)
            matched_count += 1

        pending = pending[-50:]
        alert["pendingItems"] = pending
        if not pending:
            continue

        due = not is_quiet(alert, now) and delivery_allowed(alert, now)
        if alert.get("mode") == "digest":
            local = local_time(alert, now)
            due = due and local.hour == 19 and local.minute < 30
        if not due:
            repository.upsert(alert)
            continue

        first = pending[0]
        try:
            first["notificationHeadline"] = notification_headline(
                first, str(alert.get("language") or "en-US"),
            )
        except Exception:
            # Optional AI/caching must never prevent delivery of source news.
            logging.warning("Headline enrichment unavailable; using source headline")
            first["notificationHeadline"] = str(first.get("headline") or "News update")[:90]
        title, body = notification_copy(
            pending,
            str(alert.get("locationLabel") or "your area"),
        )
        data = {
            "type": "single" if len(pending) == 1 else "group",
            "storyId": story_id(first) if len(pending) == 1 else "",
            "lat": str(first.get("lat") or ""),
            "lon": str(first.get("lon") or ""),
            "slot": slot.astimezone(timezone.utc).isoformat(),
            "count": str(len(pending)),
        }
        try:
            sender.send(str(alert["fcmToken"]), title, body, data)
        except Exception:
            logging.exception(
                "FCM delivery failed for installation %s",
                alert.get("installationId"),
            )
            repository.upsert(alert)
            continue

        seen.update(story_id(value) for value in pending)
        alert["seenStoryIds"] = list(seen)[-300:]
        alert["pendingItems"] = []
        delivery_times = []
        for value in alert.get("deliveryTimes", []):
            try:
                parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
                if now - parsed < timedelta(hours=24):
                    delivery_times.append(parsed.isoformat())
            except ValueError:
                continue
        delivery_times.append(now.isoformat())
        alert["deliveryTimes"] = delivery_times[-10:]
        alert["lastDeliveredAt"] = now.isoformat()
        repository.upsert(alert)
        sent_count += 1

    return {
        "alerts": len(alerts),
        "matched": matched_count,
        "sent": sent_count,
    }


def _notification_item(
    story: dict,
    identifier: str,
    point: tuple[float, float],
) -> dict:
    return {
        "id": identifier,
        "headline": str(
            story.get("headline")
            or story.get("title")
            or story.get("headlineEnglish")
            or story.get("headlineKannada")
            or ""
        )[:300],
        "place": str(story.get("place") or "")[:120],
        "country": str(story.get("country") or "")[:100],
        "source": str(story.get("source") or "")[:150],
        "url": str(story.get("url") or "")[:1500],
        "lat": point[0],
        "lon": point[1],
    }
