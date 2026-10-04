from __future__ import annotations

import json
import os

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


def sender_configuration_error() -> str | None:
    try:
        info = json.loads(os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", ""))
        expected = os.getenv("FIREBASE_PROJECT_ID", "globe-news-ecafc")
        if info.get("project_id") != expected:
            return "Notification sender project does not match the app."
        if not info.get("private_key") or not info.get("client_email"):
            return "Notification sender credentials are incomplete."
    except (ValueError, TypeError, AttributeError):
        return "Notification sender is not configured."
    return None


class FcmSender:
    def __init__(self):
        error = sender_configuration_error()
        if error:
            raise RuntimeError(error)
        raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", "")
        if not raw:
            raise RuntimeError("Firebase service account is not configured")
        info = json.loads(raw)
        self._project_id = str(info["project_id"])
        self._credentials = service_account.Credentials.from_service_account_info(
            info,
            scopes=[_SCOPE],
        )

    def send(
        self,
        token: str,
        title: str,
        body: str,
        data: dict[str, str],
    ) -> str:
        if not self._credentials.valid:
            # google-auth's default refresh timeout is much longer than our API budget.
            self._credentials.refresh(
                lambda **kwargs: Request()(**{**kwargs, "timeout": 8})
            )
        response = requests.post(
            f"https://fcm.googleapis.com/v1/projects/{self._project_id}/messages:send",
            headers={
                "Authorization": f"Bearer {self._credentials.token}",
                "Content-Type": "application/json",
            },
            json={
                "message": {
                    "token": token,
                    "notification": {"title": title, "body": body},
                    "data": {key: str(value) for key, value in data.items()},
                    "android": {
                        "priority": "high",
                        "notification": {
                            "channel_id": "nearby_news",
                            "icon": "ic_stat_globe_news",
                            "color": "#A8F000",
                            "sound": "default",
                            "default_vibrate_timings": True,
                        },
                    },
                }
            },
            timeout=(5, 20),
        )
        response.raise_for_status()
        name = response.json().get("name")
        if not isinstance(name, str) or not name:
            raise ValueError("FCM did not acknowledge the message")
        return name
