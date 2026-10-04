from __future__ import annotations

import os
from datetime import datetime, timezone

from azure.cosmos import exceptions
from service_clients import cosmos_client


class NewsAlertRepository:
    def __init__(self):
        client = cosmos_client()
        database = client.get_database_client(
            os.getenv("BIDAR_COSMOS_DATABASE", "gdelt_news")
        )
        self._container = database.get_container_client(
            os.getenv("NEWS_ALERTS_COSMOS_CONTAINER", "news_alerts")
        )

    def get(self, installation_id: str) -> dict | None:
        try:
            return self._container.read_item(
                item=installation_id,
                partition_key=installation_id,
            )
        except exceptions.CosmosResourceNotFoundError:
            return None

    def upsert(self, document: dict) -> dict:
        document["updatedAt"] = datetime.now(timezone.utc).isoformat()
        return self._container.upsert_item(document)

    def delete(self, installation_id: str) -> None:
        try:
            self._container.delete_item(
                item=installation_id,
                partition_key=installation_id,
            )
        except exceptions.CosmosResourceNotFoundError:
            pass

    def active(self) -> list[dict]:
        query = """
        SELECT * FROM c
        WHERE c.documentType = "newsAlert" AND c.enabled = true
        """
        return list(
            self._container.query_items(
                query=query,
                enable_cross_partition_query=True,
            )
        )
