from __future__ import annotations

import os
from datetime import datetime, timezone

from azure.cosmos import exceptions
from service_clients import cosmos_client

from .config import CITY_PARTITION, COSMOS_CONTAINER, COSMOS_DATABASE


class CityNewsRepository:
    def __init__(self):
        client = cosmos_client()
        database = client.get_database_client(COSMOS_DATABASE)
        self._container = database.get_container_client(COSMOS_CONTAINER)

    def get(self, item_id: str) -> dict | None:
        try:
            return self._container.read_item(
                item=item_id,
                partition_key=CITY_PARTITION,
            )
        except exceptions.CosmosResourceNotFoundError:
            return None

    def upsert(self, document: dict) -> dict:
        document["city"] = CITY_PARTITION
        document["updatedAt"] = datetime.now(timezone.utc).isoformat()
        return self._container.upsert_item(document)

    def map_items(self, since_iso: str, limit: int = 1000) -> list[dict]:
        query = """
        SELECT TOP @limit c.id, c.clusterId, c.primaryLocation, c.tone,
            c.color, c.canonicalUrl, c.source, c.aiReady, c.hasEmbedding,
            c.pulseStrength, c.datePublished, c.headlineEnglish,
            c.headlineKannada
        FROM c
        WHERE c.city = @city
          AND c.documentType = "article"
          AND c.mapVisible = true
          AND c.datePublished >= @since
        ORDER BY c.datePublished DESC
        """
        params = [
            {"name": "@limit", "value": min(max(limit, 1), 1000)},
            {"name": "@city", "value": CITY_PARTITION},
            {"name": "@since", "value": since_iso},
        ]
        return list(
            self._container.query_items(
                query=query,
                parameters=params,
                partition_key=CITY_PARTITION,
            )
        )
