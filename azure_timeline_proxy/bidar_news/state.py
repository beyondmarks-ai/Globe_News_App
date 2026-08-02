import json
from datetime import datetime, timezone

from azure.core.exceptions import ResourceNotFoundError
from azure.storage.blob import BlobServiceClient, ContentSettings


_CONTAINER = "bidar-ingestion-state"
_BLOB = "vijaya-karnataka/discovery.json"


class DiscoveryStateStore:
    def __init__(self, connection_string: str):
        service = BlobServiceClient.from_connection_string(connection_string)
        container = service.get_container_client(_CONTAINER)
        try:
            container.create_container()
        except Exception as error:
            if "ContainerAlreadyExists" not in str(error):
                raise
        self._blob = container.get_blob_client(_BLOB)

    def load(self) -> dict:
        try:
            return json.loads(self._blob.download_blob().readall())
        except ResourceNotFoundError:
            return {}
        except (TypeError, json.JSONDecodeError):
            return {}

    def save(self, state: dict) -> None:
        state["savedAt"] = datetime.now(timezone.utc).isoformat()
        self._blob.upload_blob(
            json.dumps(state, ensure_ascii=False, separators=(",", ":")),
            overwrite=True,
            content_settings=ContentSettings(content_type="application/json"),
        )
