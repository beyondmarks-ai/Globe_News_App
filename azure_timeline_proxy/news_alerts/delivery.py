"""A credential-protected test sends to one saved device, never a topic."""
import hmac
from datetime import datetime, timezone
from uuid import uuid4

from .models import valid_credentials, secret_hash


def send_device_test(repository, installation_id, device_secret, sender_factory):
    if not valid_credentials(installation_id, device_secret):
        return {"error": "Invalid device credentials"}, 403
    alert = repository.get(installation_id)
    if not alert:
        return {"error": "Alert not found"}, 404
    if not hmac.compare_digest(str(alert.get("deviceSecretHash") or ""), secret_hash(device_secret)):
        return {"error": "Invalid device credentials"}, 403
    if not alert.get("enabled"):
        return {"error": "Enable area alerts before sending a test"}, 409
    now = datetime.now(timezone.utc)
    previous = alert.get("lastTestAt")
    if previous:
        try:
            if (now - datetime.fromisoformat(previous)).total_seconds() < 60:
                return {"error": "Wait one minute before another test"}, 429
        except (ValueError, TypeError):
            pass
    # Reserve the cooldown before sending so retries cannot flood this device.
    alert["lastTestAt"] = now.isoformat()
    repository.upsert(alert)
    test_id = uuid4().hex
    name = sender_factory().send(
        alert["fcmToken"], "Globe News test",
        "Notifications are reaching this device. Your news area is " + str(alert.get("locationLabel") or "saved")[:120],
        {"type": "test", "test": "true", "testId": test_id},
    )
    return {"accepted": True, "messageId": name, "testId": test_id}, 200
