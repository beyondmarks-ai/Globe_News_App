import os
import unittest
from unittest.mock import Mock, patch

from bidar_news.api import detail_payload, map_payload, parse_since
from bidar_news.geocoder import verified_location
from bidar_news.processor import _tone_color, decode_message


class FakeRepository:
    def map_items(self, since):
        del since
        return [
            {
                "id": "vk:1",
                "clusterId": "bidar-vk-1",
                "primaryLocation": {
                    "name": "Mailoor",
                    "geometry": {
                        "type": "Point",
                        "coordinates": [77.5312, 17.9011],
                    },
                },
                "canonicalUrl": "https://example.com/story",
                "source": "Vijaya Karnataka",
                "tone": -3.2,
                "color": "red",
                "aiReady": True,
                "hasEmbedding": False,
                "pulseStrength": 1.0,
            }
        ]


class CityNewsTest(unittest.TestCase):
    def test_map_payload_keeps_longitude_latitude_storage_order(self):
        item = map_payload(FakeRepository(), "2026-08-01T00:00:00+00:00")["items"][0]
        self.assertEqual(item["lon"], 77.5312)
        self.assertEqual(item["lat"], 17.9011)
        self.assertTrue(item["ai_ready"])

    def test_since_requires_timezone(self):
        with self.assertRaises(ValueError):
            parse_since("2026-08-01T00:00:00")
        self.assertEqual(
            parse_since("2026-08-01T05:30:00+05:30"),
            "2026-08-01T00:00:00+00:00",
        )

    def test_district_marker_requires_location_evidence(self):
        self.assertIsNone(
            verified_location(
                {
                    "locationLevel": "district",
                    "primaryEventLocation": "Bidar",
                    "evidence": {"locationText": None},
                }
            )
        )
        location = verified_location(
            {
                "locationLevel": "district",
                "primaryEventLocation": "Bidar",
                "evidence": {"locationText": "????? ???????????"},
            }
        )
        self.assertEqual(location["geometry"]["coordinates"], [77.5301, 17.9133])

    @patch("bidar_news.geocoder.requests.get")
    def test_precise_geocode_is_bounded(self, get):
        get.return_value = Mock(
            status_code=200,
            json=lambda: {
                "features": [
                    {
                        "geometry": {"coordinates": [77.5312, 17.9011]},
                        "properties": {"confidence": "High"},
                    }
                ]
            },
        )
        get.return_value.raise_for_status = Mock()
        with patch.dict(os.environ, {"BIDAR_AZURE_MAPS_KEY": "test"}):
            location = verified_location(
                {
                    "locationLevel": "locality",
                    "primaryEventLocation": "Mailoor",
                    "evidence": {"locationText": "???????????"},
                }
            )
        self.assertEqual(location["confidence"], 0.95)
        params = get.call_args.kwargs["params"]
        self.assertIn("India", params["query"])
        self.assertIn("bbox", params)
        self.assertNotIn("subscription-key", params)

    def test_uncertain_location_has_no_dot(self):
        self.assertIsNone(
            verified_location(
                {
                    "locationLevel": "uncertain",
                    "primaryEventLocation": "Somewhere",
                    "evidence": {"locationText": "possibly"},
                }
            )
        )

    def test_queue_message_and_tone_colors(self):
        self.assertEqual(
            decode_message(b'{"sourceArticleId":"1"}')["sourceArticleId"], "1"
        )
        self.assertEqual(_tone_color(-1), "red")
        self.assertEqual(_tone_color(0), "yellow")
        self.assertEqual(_tone_color(1), "green")

    def test_detail_preserves_sources_and_evidence(self):
        payload = detail_payload(
            {
                "id": "vk:1",
                "headlineKannada": "????????",
                "sources": [{"name": "Vijaya Karnataka", "url": "https://example.com"}],
                "evidence": {"locationText": "???????????"},
            }
        )
        self.assertEqual(payload["locationEvidence"], "???????????")
        self.assertEqual(len(payload["sourceLinks"]), 1)


if __name__ == "__main__":
    unittest.main()
