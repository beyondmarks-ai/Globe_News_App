"""Reuse SDK connections and bound retries on interactive request paths."""
import os
from functools import lru_cache

from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient, ExponentialRetry


@lru_cache(maxsize=1)
def cosmos_client():
    return CosmosClient(
        os.environ['BIDAR_COSMOS_ENDPOINT'],
        credential=os.environ['BIDAR_COSMOS_KEY'],
        timeout=8, connection_timeout=4, retry_total=1,
    )


@lru_cache(maxsize=1)
def blob_service():
    return BlobServiceClient.from_connection_string(
        os.environ['AzureWebJobsStorage'],
        connection_timeout=3, read_timeout=5,
        retry_policy=ExponentialRetry(initial_backoff=0.2, increment_base=0.2,
            retry_total=1, random_jitter_range=0),
    )
