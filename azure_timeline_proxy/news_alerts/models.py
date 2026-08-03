from __future__ import annotations

import hashlib
import math
import re
from datetime import datetime, timedelta, timezone

SUPPORTED_RADII = {2_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000}
SUPPORTED_LANGUAGES = {"en-US", "kn-IN", "hi-IN", "ur-PK"}
SUPPORTED_MODES = {"smart", "immediate", "digest"}
SUPPORTED_LOCATION_TYPES = {"region", "district", "place", "locality"}
_ID_PATTERN = re.compile(r"^[a-f0-9]{32}$")
_SECRET_PATTERN = re.compile(r"^[a-f0-9]{64}$")


class AlertValidationError(ValueError):
    pass


def secret_hash(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def parse_alert(body: object) -> dict:
    if not isinstance(body, dict):
        raise AlertValidationError("Invalid request")
    installation_id = str(body.get("installationId") or "").lower()
    secret = str(body.get("deviceSecret") or "").lower()
    token = str(body.get("fcmToken") or "").strip()
    center = body.get("center")
    coordinates = center.get("coordinates") if isinstance(center, dict) else None
    try:
        longitude = float(coordinates[0])
        latitude = float(coordinates[1])
        radius = int(body.get("radiusMeters"))
        offset = int(body.get("timezoneOffsetMinutes", 0))
    except (TypeError, ValueError, IndexError):
        raise AlertValidationError("Invalid request") from None

    language = str(body.get("language") or "")
    mode = str(body.get("mode") or "")
    location_type = str(body.get("locationType") or "place")
    scope_type = str(body.get("scopeType") or "radius")
    bounds = _parse_bounds(body.get("boundingBox"))
    label = str(body.get("locationLabel") or "Saved area").strip()[:120]
    quiet = body.get("quietHours")
    if (
        not _ID_PATTERN.fullmatch(installation_id)
        or not _SECRET_PATTERN.fullmatch(secret)
        or not 20 <= len(token) <= 4096
        or not -180 <= longitude <= 180
        or not -90 <= latitude <= 90
        or radius not in SUPPORTED_RADII
        or language not in SUPPORTED_LANGUAGES
        or mode not in SUPPORTED_MODES
        or location_type not in SUPPORTED_LOCATION_TYPES
        or scope_type not in {"bounds", "radius"}
        or (scope_type == "bounds" and bounds is None)
        or not -720 <= offset <= 840
    ):
        raise AlertValidationError("Invalid request")

    return {
        "id": installation_id,
        "installationId": installation_id,
        "documentType": "newsAlert",
        "deviceSecretHash": secret_hash(secret),
        "fcmToken": token,
        "platform": "android",
        "center": {
            "type": "Point",
            "coordinates": [longitude, latitude],
        },
        "locationLabel": label or "Saved area",
        "locationType": location_type,
        "scopeType": scope_type,
        "boundingBox": bounds,
        "radiusMeters": radius,
        "language": language,
        "mode": mode,
        "timezoneOffsetMinutes": offset,
        "quietHours": {
            "enabled": bool(isinstance(quiet, dict) and quiet.get("enabled")),
            "start": "22:00",
            "end": "07:00",
        },
        "enabled": body.get("enabled") is not False,
    }


def _parse_bounds(value: object) -> list[float] | None:
    if not isinstance(value, list) or len(value) != 4:
        return None
    try:
        bounds = [float(item) for item in value]
    except (TypeError, ValueError):
        return None
    if (
        bounds[0] < -180
        or bounds[2] > 180
        or bounds[1] < -90
        or bounds[3] > 90
        or bounds[0] >= bounds[2]
        or bounds[1] >= bounds[3]
    ):
        return None
    return bounds


def valid_credentials(installation_id: str, secret: str) -> bool:
    return bool(
        _ID_PATTERN.fullmatch(installation_id.lower())
        and _SECRET_PATTERN.fullmatch(secret.lower())
    )


def distance_meters(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    radius = 6_371_008.8
    phi1 = math.radians(a_lat)
    phi2 = math.radians(b_lat)
    delta_phi = math.radians(b_lat - a_lat)
    delta_lambda = math.radians(b_lon - a_lon)
    value = (
        math.sin(delta_phi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    )
    return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))


def point_matches_alert(alert: dict, latitude: float, longitude: float) -> bool:
    if alert.get("scopeType") == "bounds":
        bounds = _parse_bounds(alert.get("boundingBox"))
        return bool(
            bounds
            and bounds[0] <= longitude <= bounds[2]
            and bounds[1] <= latitude <= bounds[3]
        )
    try:
        center = alert["center"]["coordinates"]
        center_lon, center_lat = float(center[0]), float(center[1])
        radius = int(alert["radiusMeters"])
    except (KeyError, TypeError, ValueError, IndexError):
        return False
    return distance_meters(center_lat, center_lon, latitude, longitude) <= radius


def story_point(story: dict) -> tuple[float, float] | None:
    try:
        latitude = float(story.get("lat", story.get("latitude")))
        longitude = float(
            story.get("lon", story.get("lng", story.get("longitude")))
        )
    except (TypeError, ValueError):
        return None
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return None
    return latitude, longitude


def story_id(story: dict) -> str:
    value = str(story.get("id") or "").strip()
    if value:
        return value[:300]
    basis = "|".join(
        str(story.get(key) or "") for key in ("url", "headline", "lat", "lon")
    )
    return hashlib.sha256(basis.encode("utf-8")).hexdigest()


def local_time(alert: dict, now: datetime) -> datetime:
    return now.astimezone(timezone.utc) + timedelta(
        minutes=int(alert.get("timezoneOffsetMinutes", 0))
    )


def is_quiet(alert: dict, now: datetime) -> bool:
    quiet = alert.get("quietHours")
    if not isinstance(quiet, dict) or not quiet.get("enabled"):
        return False
    hour = local_time(alert, now).hour
    return hour >= 22 or hour < 7


def delivery_allowed(alert: dict, now: datetime) -> bool:
    parsed = []
    for value in alert.get("deliveryTimes", []):
        try:
            parsed.append(datetime.fromisoformat(str(value).replace("Z", "+00:00")))
        except ValueError:
            continue
    recent_day = [value for value in parsed if now - value < timedelta(hours=24)]
    recent_hour = [value for value in recent_day if now - value < timedelta(hours=1)]
    return len(recent_hour) < 3 and len(recent_day) < 10


def notification_copy(items: list[dict], location_label: str) -> tuple[str, str]:
    count = len(items)
    if count == 1:
        item = items[0]
        title = str(
            item.get("notificationHeadline")
            or item.get("headline")
            or "Nearby news"
        )
        place = str(item.get("place") or location_label).strip()
        source = str(item.get("source") or "").strip()
        body = " | ".join(value for value in (place, source) if value)
        return title[:90], (body or "A new story is available in your area")[:180]
    if count >= 10:
        return (
            "10+ news updates from your area",
            f"Open Globe News to explore updates in {location_label}.",
        )
    return (
        f"{count} news updates in {location_label}",
        str(
            items[0].get("notificationHeadline")
            or items[0].get("headline")
            or "Open Globe News for details"
        )[:180],
    )
