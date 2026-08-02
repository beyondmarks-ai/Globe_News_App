from __future__ import annotations

from datetime import datetime, timedelta, timezone

from .repository import CityNewsRepository


def parse_since(value: str | None) -> str:
    if not value:
        return (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    normalized = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        raise ValueError("since must include a timezone")
    return parsed.astimezone(timezone.utc).isoformat()


def map_payload(repository: CityNewsRepository, since: str) -> dict:
    items = []
    for document in repository.map_items(since):
        location = document.get("primaryLocation") or {}
        coordinates = (location.get("geometry") or {}).get("coordinates")
        if not isinstance(coordinates, list) or len(coordinates) < 2:
            continue
        items.append(
            {
                "id": document.get("clusterId") or document["id"],
                "place": location.get("name") or "Bidar",
                "country": "India",
                "lat": coordinates[1],
                "lon": coordinates[0],
                "tone": document.get("tone", 0),
                "color": document.get("color", "yellow"),
                "url": document.get("canonicalUrl"),
                "source": document.get("source", "Vijaya Karnataka"),
                "headline": document.get("headlineEnglish") or document.get("headlineKannada"),
                "has_embedding": bool(document.get("hasEmbedding", False)),
                "ai_ready": bool(document.get("aiReady", False)),
                "pulse_strength": document.get("pulseStrength", 1),
            }
        )
    return {"items": items}


def detail_payload(document: dict) -> dict:
    return {
        "id": document.get("clusterId") or document["id"],
        "title": document.get("headlineEnglish") or document.get("headlineKannada"),
        "headlineKannada": document.get("headlineKannada"),
        "headlineEnglish": document.get("headlineEnglish"),
        "whatHappened": document.get("whatHappened"),
        "when": document.get("when"),
        "where": document.get("where"),
        "why": document.get("why"),
        "how": document.get("how"),
        "imageUrl": document.get("imageUrl"),
        "originalLanguage": document.get("language", "kn-IN"),
        "articleBody": document.get("articleBody"),
        "sourceLinks": document.get("sources", []),
        "primaryLocation": document.get("primaryLocation"),
        "locationEvidence": (document.get("evidence") or {}).get("locationText"),
        "tone": document.get("tone", 0),
        "category": document.get("category", "other"),
    }
