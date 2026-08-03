from datetime import datetime, timezone
import unittest
from unittest.mock import patch

from news_alerts.processor import process_timeline_alerts


class _Repository:
    def __init__(self, alert):
        self.alert = alert

    def active(self):
        return [self.alert] if self.alert.get("enabled", True) else []

    def upsert(self, document):
        self.alert = document
        return document


class _Sender:
    def __init__(self):
        self.messages = []

    def send(self, token, title, body, data):
        self.messages.append(
            {"token": token, "title": title, "body": body, "data": data}
        )


class NewsAlertProcessorTests(unittest.TestCase):
    def _alert(self):
        return {
            "id": "a" * 32,
            "installationId": "a" * 32,
            "documentType": "newsAlert",
            "enabled": True,
            "fcmToken": "realistic-test-token",
            "center": {"type": "Point", "coordinates": [77.5301, 17.9133]},
            "locationLabel": "Bidar",
            "radiusMeters": 2000,
            "language": "en-US",
            "mode": "smart",
            "quietHours": {"enabled": False},
            "timezoneOffsetMinutes": 330,
        }

    @patch(
        "news_alerts.processor.notification_headline",
        return_value="Refined nearby headline",
    )
    def test_matches_inside_radius_and_prevents_duplicate_delivery(self, _):
        repository = _Repository(self._alert())
        sender = _Sender()
        stories = [
            {
                "id": "near",
                "headline": "Original",
                "place": "Bidar",
                "source": "Source",
                "lat": 17.914,
                "lon": 77.531,
            },
            {
                "id": "far",
                "headline": "Far away",
                "place": "Kalaburagi",
                "lat": 17.33,
                "lon": 76.83,
            },
        ]
        slot = datetime.now(timezone.utc)

        first = process_timeline_alerts(stories, slot, repository, sender)
        second = process_timeline_alerts(stories, slot, repository, sender)

        self.assertEqual(first["matched"], 1)
        self.assertEqual(first["sent"], 1)
        self.assertEqual(second["sent"], 0)
        self.assertEqual(len(sender.messages), 1)
        self.assertEqual(sender.messages[0]["title"], "Refined nearby headline")
        self.assertEqual(sender.messages[0]["data"]["storyId"], "near")


if __name__ == "__main__":
    unittest.main()
