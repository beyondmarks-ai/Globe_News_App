from __future__ import annotations

import json
import os

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


class FcmSender:
    def __init__(self):
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
    ) -> None:
        self._credentials.refresh(Request())
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
                            "sound": "default",
                            "default_vibrate_timings": True,
                        },
                    },
                }
            },
            timeout=(5, 20),
        )
        response.raise_for_status()
