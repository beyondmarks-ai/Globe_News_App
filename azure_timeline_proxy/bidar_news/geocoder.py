from __future__ import annotations

import logging
import os

import requests

from .config import BIDAR_BOUNDS, BIDAR_DISTRICT_POINT


def _inside_bidar(lon: float, lat: float) -> bool:
    return (
        BIDAR_BOUNDS["minLon"] <= lon <= BIDAR_BOUNDS["maxLon"]
        and BIDAR_BOUNDS["minLat"] <= lat <= BIDAR_BOUNDS["maxLat"]
    )


def verified_location(structured: dict) -> dict | None:
    level = structured.get("locationLevel")
    name = structured.get("primaryEventLocation")
    evidence = (structured.get("evidence") or {}).get("locationText")
    if level in {"outside_bidar", "uncertain"} or not name or not evidence:
        return None
    if level in {"city", "district"} and str(name).strip().lower() in {
        "bidar",
        "bidar city",
        "bidar district",
        "bidar city, bidar district",
        "bidar, bidar district",
        "?????",
    }:
        lon, lat = BIDAR_DISTRICT_POINT
        return {
            "name": "Bidar",
            "level": "district",
            "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "method": "district_marker",
            "confidence": 0.78,
            "evidence": evidence,
        }

    key = os.environ.get("BIDAR_AZURE_MAPS_KEY")
    if not key:
        return None
    try:
        response = requests.get(
            "https://atlas.microsoft.com/geocode",
            headers={
                "subscription-key": key,
                "Accept-Language": "en-IN",
            },
            params={
                "api-version": "2025-01-01",
                "query": f"{name}, Bidar, Karnataka, India",
                "coordinates": "77.5301,17.9133",
                "bbox": (
                    f"{BIDAR_BOUNDS['minLon']},{BIDAR_BOUNDS['minLat']},"
                    f"{BIDAR_BOUNDS['maxLon']},{BIDAR_BOUNDS['maxLat']}"
                ),
                "top": 3,
            },
            timeout=(5, 20),
        )
        response.raise_for_status()
    except requests.RequestException as error:
        logging.warning("Bidar geocoding failed: %s", type(error).__name__)
        return None
    features = response.json().get("features", [])
    for feature in features:
        coordinates = (feature.get("geometry") or {}).get("coordinates")
        if (
            isinstance(coordinates, list)
            and len(coordinates) >= 2
            and _inside_bidar(float(coordinates[0]), float(coordinates[1]))
        ):
            confidence = str(
                (feature.get("properties") or {}).get("confidence", "")
            ).lower()
            score = {"high": 0.95, "medium": 0.82, "low": 0.65}.get(confidence, 0.8)
            return {
                "name": name,
                "level": level,
                "geometry": {
                    "type": "Point",
                    "coordinates": [float(coordinates[0]), float(coordinates[1])],
                },
                "method": "ai_extracted_and_geocoded",
                "confidence": score,
                "evidence": evidence,
            }
    return None
