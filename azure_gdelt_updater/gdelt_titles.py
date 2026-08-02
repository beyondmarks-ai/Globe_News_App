import gzip
import json
import logging
from datetime import datetime, timedelta
from urllib.parse import urlparse

import requests


_GAL_OFFSETS_MINUTES = (-14, -13, -12, -11)
_GAL_URL = "http://data.gdeltproject.org/gdeltv3/gal/{timestamp}.gal.json.gz"


def article_url_key(value):
    """Return a stable key shared by GKG and GAL article URLs."""
    text = str(value or "").strip()
    if not text:
        return ""

    parsed = urlparse(text if "://" in text else f"https://{text}")
    host = parsed.netloc.lower()
    if host.endswith(":443"):
        host = host[:-4]
    elif host.endswith(":80"):
        host = host[:-3]

    return f"{host}{parsed.path.rstrip('/')}"


def load_gdelt_titles(timestamp, session=requests):
    """Load publisher-supplied titles for one 15-minute GKG slot."""
    slot = datetime.strptime(timestamp, "%Y%m%d%H%M%S")
    titles = {}

    for offset in _GAL_OFFSETS_MINUTES:
        gal_timestamp = (slot + timedelta(minutes=offset)).strftime(
            "%Y%m%d%H%M%S"
        )
        url = _GAL_URL.format(timestamp=gal_timestamp)

        try:
            response = session.get(url, timeout=45)
            if response.status_code == 404:
                continue
            response.raise_for_status()
            payload = gzip.decompress(response.content).decode(
                "utf-8", errors="replace"
            )
        except (requests.RequestException, OSError, EOFError):
            logging.warning(
                "Could not load GDELT GAL titles from %s", url, exc_info=True
            )
            continue

        for line in payload.splitlines():
            try:
                document = json.loads(line)
            except (TypeError, ValueError):
                continue

            key = article_url_key(document.get("url"))
            title = clean_title(document.get("title"))
            if key and title:
                titles[key] = title

    logging.info(
        "Loaded %s GDELT GAL titles for GKG slot %s", len(titles), timestamp
    )
    return titles


def title_for_url(titles, url):
    return titles.get(article_url_key(url), "")


def clean_title(value):
    title = " ".join(str(value or "").split()).strip()[:500]
    rejected = (
        "error:",
        "access denied",
        "page not found",
        "request could not be satisfied",
    )
    if not title or title.lower().startswith(rejected):
        return ""
    return title
