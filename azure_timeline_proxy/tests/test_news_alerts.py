from datetime import datetime, timedelta, timezone
import unittest

from news_alerts.models import (
    AlertValidationError,
    delivery_allowed,
    distance_meters,
    notification_copy,
    parse_alert,
    point_matches_alert,
)


class NewsAlertModelTests(unittest.TestCase):
    def _body(self):
        return {
            "installationId": "a" * 32,
            "deviceSecret": "b" * 64,
            "fcmToken": "token-" + ("x" * 40),
            "center": {"type": "Point", "coordinates": [77.5301, 17.9133]},
            "locationLabel": "Bidar",
            "radiusMeters": 10000,
            "language": "kn-IN",
            "mode": "smart",
            "quietHours": {"enabled": True},
            "timezoneOffsetMinutes": 330,
        }

    def test_alert_keeps_longitude_before_latitude(self):
        parsed = parse_alert(self._body())
        self.assertEqual(parsed["center"]["coordinates"], [77.5301, 17.9133])
        self.assertNotEqual(parsed["deviceSecretHash"], "b" * 64)

    def test_bounds_scope_matches_the_selected_city_area(self):
        body = self._body()
        body.update(
            {
                "locationType": "place",
                "scopeType": "bounds",
                "boundingBox": [77.325376, 12.733355, 77.783794, 13.234974],
            }
        )
        parsed = parse_alert(body)
        self.assertTrue(point_matches_alert(parsed, 12.9716, 77.5946))
        self.assertFalse(point_matches_alert(parsed, 17.9133, 77.5301))
    def test_rejects_unsupported_radius(self):
        body = self._body()
        body["radiusMeters"] = 9000
        with self.assertRaises(AlertValidationError):
            parse_alert(body)

    def test_distance_matching_uses_metres(self):
        self.assertLess(distance_meters(17.9133, 77.5301, 17.92, 77.54), 2000)
        self.assertGreater(distance_meters(17.9133, 77.5301, 18.2, 77.8), 10000)

    def test_notification_copy_groups_large_batches(self):
        items = [{"headline": "One"}, {"headline": "Two"}]
        self.assertIn("2 news updates", notification_copy(items, "Bidar")[0])
        self.assertEqual(
            notification_copy(items * 5, "Bidar")[0],
            "10+ news updates from your area",
        )

    def test_hourly_and_daily_rate_limits(self):
        now = datetime.now(timezone.utc)
        alert = {
            "deliveryTimes": [
                (now - timedelta(minutes=10)).isoformat(),
                (now - timedelta(minutes=20)).isoformat(),
                (now - timedelta(minutes=30)).isoformat(),
            ]
        }
        self.assertFalse(delivery_allowed(alert, now))


if __name__ == "__main__":
    unittest.main()
