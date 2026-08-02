import azure.functions as func
import logging
import os
import json
import csv
import io
import zipfile
import requests
import hashlib
import time
import requests
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential
from datetime import datetime, timedelta
from azure.cosmos import CosmosClient
from urllib.parse import urlparse, urlunparse
from openai import AzureOpenAI
from azure.search.documents.models import VectorizedQuery
from gdelt_titles import load_gdelt_titles, title_for_url

logging.getLogger("azure").setLevel(logging.WARNING)
logging.getLogger("azure.cosmos").setLevel(logging.WARNING)

app = func.FunctionApp()

COSMOS_ENDPOINT = os.getenv("COSMOS_ENDPOINT")
COSMOS_KEY = os.getenv("COSMOS_KEY")
COSMOS_DATABASE = os.environ.get("COSMOS_DATABASE", "gdelt_news")
EVENTS_CONTAINER = os.environ.get("COSMOS_EVENTS_CONTAINER", "live_events")
GKG_CONTAINER = os.environ.get("COSMOS_GKG_CONTAINER", "live_gkg")
AZURE_SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT")
AZURE_SEARCH_KEY = os.getenv("AZURE_SEARCH_KEY")
AZURE_SEARCH_INDEX = os.getenv("AZURE_SEARCH_INDEX", "gdelt-news-index")
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_KEY = os.getenv("AZURE_OPENAI_KEY")
AZURE_OPENAI_EMBEDDING_DEPLOYMENT = os.getenv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT", "gdelt-embedding")
AZURE_OPENAI_CHAT_DEPLOYMENT = os.getenv("AZURE_OPENAI_CHAT_DEPLOYMENT", "gpt-4o")
HISTORICAL_GKG_CONTAINER = os.environ.get("COSMOS_HISTORICAL_GKG_CONTAINER", "historical_gkg")

cosmos_client = None
db = None
events_container = None
gkg_container = None
historical_gkg_container = None
search_client = None
openai_client = None


def get_cosmos_db():
    global cosmos_client, db

    if db is None:
        if not COSMOS_ENDPOINT or not COSMOS_KEY:
            raise RuntimeError("COSMOS_ENDPOINT and COSMOS_KEY app settings are required.")

        cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=COSMOS_KEY)
        db = cosmos_client.get_database_client(COSMOS_DATABASE)

    return db

CHAT_MEMORY_CONTAINER = os.getenv("COSMOS_CHAT_MEMORY_CONTAINER", "chat_memory")
chat_memory_container = None

def get_chat_memory_container():
    global chat_memory_container

    if chat_memory_container is None:
        chat_memory_container = get_cosmos_db().get_container_client(CHAT_MEMORY_CONTAINER)

    return chat_memory_container


def get_live_containers():
    global events_container, gkg_container

    if events_container is None or gkg_container is None:
        database = get_cosmos_db()
        events_container = database.get_container_client(EVENTS_CONTAINER)
        gkg_container = database.get_container_client(GKG_CONTAINER)

    return events_container, gkg_container


def get_historical_gkg_container():
    global historical_gkg_container

    if historical_gkg_container is None:
        historical_gkg_container = get_cosmos_db().get_container_client(HISTORICAL_GKG_CONTAINER)

    return historical_gkg_container


def get_search_client():
    global search_client

    if search_client is None:
        if not AZURE_SEARCH_ENDPOINT or not AZURE_SEARCH_KEY or not AZURE_SEARCH_INDEX:
            return None

        search_client = SearchClient(
            endpoint=AZURE_SEARCH_ENDPOINT,
            index_name=AZURE_SEARCH_INDEX,
            credential=AzureKeyCredential(AZURE_SEARCH_KEY)
        )

    return search_client


def get_openai_client():
    global openai_client

    if openai_client is None:
        if not AZURE_OPENAI_ENDPOINT or not AZURE_OPENAI_KEY:
            raise RuntimeError("AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_KEY app settings are required.")

        openai_client = AzureOpenAI(
            api_key=AZURE_OPENAI_KEY,
            api_version="2024-02-15-preview",
            azure_endpoint=AZURE_OPENAI_ENDPOINT,
        )

    return openai_client


def get_required_search_client():
    client = get_search_client()

    if client is None:
        raise RuntimeError("Azure AI Search app settings are required for this endpoint.")

    return client


_embedding_cache = {}

def normalize_url(url):
    if not url:
        return ""

    url = url.strip()
    parsed = urlparse(url)

    scheme = parsed.scheme.lower() or "https"
    netloc = parsed.netloc.lower()

    if netloc.endswith(":443"):
        netloc = netloc[:-4]
    if netloc.endswith(":80"):
        netloc = netloc[:-3]

    path = parsed.path.rstrip("/")

    return urlunparse((scheme, netloc, path, "", "", ""))


def make_id(url):
    clean_url = normalize_url(url)
    return hashlib.sha256(clean_url.encode("utf-8")).hexdigest()

def has_embedding(url):
    client = get_search_client()

    if client is None:
        return False

    try:
        results = client.search(
            search_text=url,
            search_fields=["url"],
            select=["id", "url"],
            top=1
        )

        for r in results:
            if r.get("url") == url:
                return True

        return False

    except Exception as e:
        print("Embedding check error:", e)
        return False

def add_ai_flags(item, url):
    ready = has_embedding(url)
    item["has_embedding"] = ready
    item["ai_ready"] = ready
    item["pulse_strength"] = 1.0 if ready else 0.0
    return item

def get_latest_timestamp():
    now = datetime.utcnow()
    minute = (now.minute // 15) * 15
    slot = now.replace(minute=minute, second=0, microsecond=0)

    # Use previous slot because GDELT files may appear slightly late
    slot = slot - timedelta(minutes=15)

    return slot.strftime("%Y%m%d%H%M%S"), slot.strftime("%Y-%m-%d")


def color_from_tone(tone):
    if tone is None:
        return "yellow"
    if tone < -2:
        return "red"
    if tone > 2:
        return "green"
    return "yellow"


def download_zip(url):
    r = requests.get(url, timeout=90)
    if r.status_code != 200:
        logging.warning(f"Missing file: {url} status={r.status_code}")
        return None

    if not r.content.startswith(b"PK"):
        logging.warning(f"Invalid ZIP: {url}")
        return None

    return r.content


def extract_csv_from_zip(zip_bytes):
    with zipfile.ZipFile(io.BytesIO(zip_bytes), "r") as z:
        name = z.namelist()[0]
        data = z.read(name).decode("utf-8", errors="ignore")
        return data


def process_events(ts, date):
    events, _ = get_live_containers()
    url = f"http://data.gdeltproject.org/gdeltv2/{ts}.export.CSV.zip"
    zip_bytes = download_zip(url)

    if not zip_bytes:
        return 0

    csv_text = extract_csv_from_zip(zip_bytes)
    reader = csv.reader(io.StringIO(csv_text), delimiter="\t")

    inserted = 0

    for i, row in enumerate(reader):
        try:
            if len(row) < 61:
                continue

            tone = float(row[34]) if row[34] else None
            lat = float(row[56]) if row[56] else None
            lon = float(row[57]) if row[57] else None

            if lat is None or lon is None:
                continue

            item = {
                "id": f"event-{ts}-{row[0]}",
                "date": date,
                "timestamp": ts,
                "type": "event",
                "globalEventId": row[0],
                "actor1": row[6],
                "actor2": row[16],
                "eventCode": row[26],
                "place": row[52],
                "country": row[53],
                "lat": lat,
                "lon": lon,
                "tone": tone,
                "color": color_from_tone(tone),
                "url": row[60]
            }

            events.upsert_item(item)
            inserted += 1

        except Exception as e:
            logging.warning(f"Event row skipped: {e}")

    return inserted


def parse_gkg_locations(locations_text):
    if not locations_text:
        return []

    locations = []

    for part in locations_text.split(";"):
        pieces = part.split("#")

        if len(pieces) >= 7:
            try:
                locations.append({
                    "place": pieces[1],
                    "country": pieces[2],
                    "lat": float(pieces[5]),
                    "lon": float(pieces[6])
                })
            except:
                pass

    return locations


def process_gkg(ts, date):
    _, gkg = get_live_containers()
    url = f"http://data.gdeltproject.org/gdeltv2/{ts}.gkg.csv.zip"
    zip_bytes = download_zip(url)

    if not zip_bytes:
        return 0

    csv_text = extract_csv_from_zip(zip_bytes)
    reader = csv.reader(io.StringIO(csv_text), delimiter="\t")
    titles = load_gdelt_titles(ts)

    inserted = 0

    for i, row in enumerate(reader):
        try:
            if len(row) < 16:
                continue

            article_url = row[4]
            headline = title_for_url(titles, article_url)
            source = row[3]
            themes = row[8] if len(row) > 8 else ""
            locations_text = row[10] if len(row) > 10 else ""
            persons = row[12] if len(row) > 12 else ""
            organizations = row[14] if len(row) > 14 else ""

            tone_parts = row[15].split(",") if row[15] else []
            tone = float(tone_parts[0]) if tone_parts else None

            locations = parse_gkg_locations(locations_text)

            for loc_index, loc in enumerate(locations):
                item = {
                    "id": f"gkg-{ts}-{i}-{loc_index}",
                    "date": date,
                    "timestamp": ts,
                    "type": "gkg",
                    "source": source,
                    "url": article_url,
                    "headline": headline,
                    "place": loc["place"],
                    "country": loc["country"],
                    "lat": loc["lat"],
                    "lon": loc["lon"],
                    "tone": tone,
                    "color": color_from_tone(tone),
                    "themes": themes,
                    "persons": persons,
                    "organizations": organizations
                }

                gkg.upsert_item(item)
                inserted += 1

        except Exception as e:
            logging.warning(f"GKG row skipped: {e}")

    return inserted


@app.timer_trigger(
    schedule="0 */15 * * * *",
    arg_name="myTimer",
    run_on_startup=False,
    use_monitor=False
)
def gdelt_15min_timer(myTimer: func.TimerRequest) -> None:
    ts, date = get_latest_timestamp()

    logging.info(f"Processing GDELT timestamp: {ts}")

    event_count = process_events(ts, date)
    gkg_count = process_gkg(ts, date)

    logging.info(f"Inserted events: {event_count}")
    logging.info(f"Inserted gkg: {gkg_count}")

@app.route(route="get_map_data", auth_level=func.AuthLevel.FUNCTION)
def get_map_data(req: func.HttpRequest) -> func.HttpResponse:
    try:
        date = req.params.get("date")
        timestamp = req.params.get("timestamp")
        data_type = req.params.get("type", "gkg")
        limit = int(req.params.get("limit", "500"))

        if limit > 1000:
            limit = 1000

        if not date:
            return func.HttpResponse(
                json.dumps({"error": "Missing required query parameter: date"}),
                status_code=400,
                mimetype="application/json"
            )

        live_events, live_gkg = get_live_containers()
        container = live_events if data_type == "events" else live_gkg

        if timestamp:
            query = f"""
            SELECT TOP {limit}
                c.id, c.date, c.timestamp, c.type,
                c.place, c.country, c.lat, c.lon,
                c.tone, c.color, c.url, c.source,
                c.headline,
                c.actor1, c.actor2, c.eventCode,
                c.themes, c.persons, c.organizations
            FROM c
            WHERE c.date = @date AND c.timestamp = @timestamp
            """
            parameters = [
                {"name": "@date", "value": date},
                {"name": "@timestamp", "value": timestamp}
            ]
        else:
            query = f"""
            SELECT TOP {limit}
                c.id, c.date, c.timestamp, c.type,
                c.place, c.country, c.lat, c.lon,
                c.tone, c.color, c.url, c.source,
                c.headline,
                c.actor1, c.actor2, c.eventCode,
                c.themes, c.persons, c.organizations
            FROM c
            WHERE c.date = @date
            """
            parameters = [
                {"name": "@date", "value": date}
            ]

        items = list(container.query_items(
            query=query,
            parameters=parameters,
            enable_cross_partition_query=True
        ))

        # Add AI-ready flags for globe ripple markers.
        for item in items:
            if item.get("url"):
                add_ai_flags(item, item.get("url"))
            else:
                item["has_embedding"] = False
                item["ai_ready"] = False
                item["pulse_strength"] = 0.0

        return func.HttpResponse(
            json.dumps(items, default=str),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("get_map_data failed")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
@app.route(route="historical_data", auth_level=func.AuthLevel.FUNCTION)
def historical_data(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps({"status": "historical api working"}),
        mimetype="application/json",
        status_code=200
    )
@app.route(route="historical_data_v2", auth_level=func.AuthLevel.FUNCTION)
def historical_data_v2(req: func.HttpRequest) -> func.HttpResponse:
    try:
        date = req.params.get("date")
        timestamp = req.params.get("timestamp")
        limit = int(req.params.get("limit", "100"))

        if not date:
            return func.HttpResponse(
                json.dumps({"error": "Missing required query parameter: date"}),
                status_code=400,
                mimetype="application/json"
            )

        if limit > 1000:
            limit = 1000

        if timestamp:
            query = f"""
            SELECT TOP {limit} *
            FROM c
            WHERE c.date = @date AND c.timestamp = @timestamp
            """
            parameters = [
                {"name": "@date", "value": date},
                {"name": "@timestamp", "value": timestamp}
            ]
        else:
            query = f"""
            SELECT TOP {limit} *
            FROM c
            WHERE c.date = @date
            """
            parameters = [
                {"name": "@date", "value": date}
            ]

        items = list(get_historical_gkg_container().query_items(
            query=query,
            parameters=parameters,
            enable_cross_partition_query=True
        ))

        clean_data = []

        for item in items:
            locations = parse_gkg_locations(item.get("locations", ""))

            tone = item.get("tone")
            if tone is None:
                tone_data = item.get("tone_data", "")
                if tone_data:
                    try:
                        tone = float(tone_data.split(",")[0])
                    except:
                        tone = None

            # If document already has lat/lon, use it directly
            if item.get("lat") is not None and item.get("lon") is not None:
                url = item.get("url")
                clean_data.append(add_ai_flags({
                    "id": item.get("id"),
                    "date": item.get("date"),
                    "timestamp": item.get("timestamp"),
                    "place": item.get("place"),
                    "country": item.get("country"),
                    "lat": item.get("lat"),
                    "lon": item.get("lon"),
                    "tone": tone,
                    "color": item.get("color") or color_from_tone(tone),
                    "url": url,
                    "source": item.get("source"),
                    "headline": item.get("headline")
                }, url))
            else:
                # Old cached documents only have locations string
                for loc in locations:
                    url = item.get("url")
                    clean_data.append(add_ai_flags({
                        "id": item.get("id"),
                        "date": item.get("date"),
                        "timestamp": item.get("timestamp"),
                        "place": loc.get("place"),
                        "country": loc.get("country"),
                        "lat": loc.get("lat"),
                        "lon": loc.get("lon"),
                        "tone": tone,
                        "color": color_from_tone(tone),
                        "url": url,
                        "source": item.get("source"),
                        "headline": item.get("headline")
                    }, url))

                    if len(clean_data) >= limit:
                        break

            if len(clean_data) >= limit:
                break

        return func.HttpResponse(
            json.dumps(clean_data, default=str),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("historical_data_v2 failed")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

@app.route(route="timeline_news", auth_level=func.AuthLevel.FUNCTION)
def timeline_news(req: func.HttpRequest) -> func.HttpResponse:
    try:
        date = req.params.get("date")
        time = req.params.get("time")
        limit = int(req.params.get("limit", "500"))

        if not date or not time:
            return func.HttpResponse(
                json.dumps({"error": "Use ?date=2025-08-15&time=02:15"}),
                status_code=400,
                mimetype="application/json"
            )

        if limit > 1000:
            limit = 1000

        y, m, d = date.split("-")
        hh, mm = time.split(":")
        ts = f"{y}{m}{d}{hh}{mm}00"

        query = f"""
        SELECT TOP 5000 *
        FROM c
        WHERE c.timestamp = @timestamp
        """

        params = [{"name": "@timestamp", "value": ts}]

        cached = list(get_historical_gkg_container().query_items(
            query=query,
            parameters=params,
            enable_cross_partition_query=True
        ))

        if cached:
            clean_data = []
            seen_urls = set()
            titles = load_gdelt_titles(ts)

            for item in cached:
                url = item.get("url")

                if not url or url in seen_urls:
                    continue

                seen_urls.add(url)

                tone = item.get("tone")
                if tone is None:
                    tone_data = item.get("tone_data", "")
                    if tone_data:
                        try:
                            tone = float(tone_data.split(",")[0])
                        except:
                            tone = None

                ready = has_embedding(url)

                if item.get("lat") is not None and item.get("lon") is not None:
                    clean_data.append({
                        "id": item.get("id"),
                        "date": item.get("date"),
                        "timestamp": item.get("timestamp"),
                        "place": item.get("place"),
                        "country": item.get("country"),
                        "lat": item.get("lat"),
                        "lon": item.get("lon"),
                        "tone": tone,
                        "color": item.get("color") or color_from_tone(tone),
                        "url": url,
                        "source": item.get("source"),
                        "headline": item.get("headline") or title_for_url(titles, url),
                        "has_embedding": ready,
                        "ai_ready": ready,
                        "pulse_strength": 1.0 if ready else 0.0
                    })
                else:
                    locations = parse_gkg_locations(item.get("locations", ""))

                    if not locations:
                        continue

                    loc = locations[0]

                    ready = has_embedding(url)

                    clean_data.append({
                        "id": item.get("id"),
                        "date": item.get("date"),
                        "timestamp": item.get("timestamp"),
                        "place": loc.get("place"),
                        "country": loc.get("country"),
                        "lat": loc.get("lat"),
                        "lon": loc.get("lon"),
                        "tone": tone,
                        "color": color_from_tone(tone),
                        "url": url,
                        "source": item.get("source"),
                        "headline": item.get("headline") or title_for_url(titles, url),
                        "has_embedding": ready,
                        "ai_ready": ready,
                        "pulse_strength": 1.0 if ready else 0.0
                    })

                if len(clean_data) >= limit:
                    break

            return func.HttpResponse(
                json.dumps({
                    "source": "cosmos_cache_unique_urls",
                    "timestamp": ts,
                    "count": len(clean_data),
                    "data": clean_data
                }, default=str),
                status_code=200,
                mimetype="application/json"
            )

        url = f"http://data.gdeltproject.org/gdeltv2/{ts}.gkg.csv.zip"
        zip_bytes = download_zip(url)

        if not zip_bytes:
            return func.HttpResponse(
                json.dumps({
                    "source": "gdelt",
                    "timestamp": ts,
                    "count": 0,
                    "data": [],
                    "message": "GDELT file not available"
                }),
                status_code=200,
                mimetype="application/json"
            )

        csv_text = extract_csv_from_zip(zip_bytes)
        reader = csv.reader(io.StringIO(csv_text), delimiter="\t")
        titles = load_gdelt_titles(ts)

        results = []
        inserted = 0
        seen_urls = set()

        for i, row in enumerate(reader):
            try:
                if len(row) < 16:
                    continue

                article_url = row[4]
                headline = title_for_url(titles, article_url)

                if not article_url or article_url in seen_urls:
                    continue

                seen_urls.add(article_url)

                source = row[3]
                themes = row[8] if len(row) > 8 else ""
                locations_text = row[10] if len(row) > 10 else ""
                persons = row[12] if len(row) > 12 else ""
                organizations = row[14] if len(row) > 14 else ""

                tone_parts = row[15].split(",") if row[15] else []
                tone = float(tone_parts[0]) if tone_parts else None

                locations = parse_gkg_locations(locations_text)

                if not locations:
                    continue

                loc = locations[0]

                item = {
                    "id": f"hist-gkg-{ts}-{i}",
                    "date": date,
                    "timestamp": ts,
                    "type": "gkg",
                    "source": source,
                    "url": article_url,
                    "headline": headline,
                    "place": loc["place"],
                    "country": loc["country"],
                    "lat": loc["lat"],
                    "lon": loc["lon"],
                    "tone": tone,
                    "color": color_from_tone(tone),
                    "themes": themes,
                    "locations": locations_text,
                    "persons": persons,
                    "organizations": organizations,
                    "tone_data": row[15] if len(row) > 15 else ""
                }

                get_historical_gkg_container().upsert_item(item)

                if len(results) < limit:
                    results.append(add_ai_flags({
                        "id": item["id"],
                        "date": item["date"],
                        "timestamp": item["timestamp"],
                        "place": item["place"],
                        "country": item["country"],
                        "lat": item["lat"],
                        "lon": item["lon"],
                        "tone": item["tone"],
                        "color": item["color"],
                        "url": item["url"],
                        "source": item["source"],
                        "headline": item["headline"]
                    }, item["url"]))

                inserted += 1

                if len(results) >= limit:
                    break

            except Exception as e:
                logging.warning(f"timeline_news row skipped: {e}")

        return func.HttpResponse(
            json.dumps({
                "source": "gdelt_download_unique_urls",
                "timestamp": ts,
                "inserted": inserted,
                "count": len(results),
                "data": results
            }, default=str),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("timeline_news failed")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


def load_chat_memory(session_id, limit=12):
    if not session_id:
        return []

    container = get_chat_memory_container()

    query = """
    SELECT TOP @limit c.role, c.content, c.created_at
    FROM c
    WHERE c.session_id = @session_id
    ORDER BY c.created_at DESC
    """

    items = list(container.query_items(
        query=query,
        parameters=[
            {"name": "@session_id", "value": session_id},
            {"name": "@limit", "value": limit}
        ],
        partition_key=session_id
    ))

    items.reverse()
    return items


def save_chat_message(session_id, role, content):
    if not session_id:
        return

    container = get_chat_memory_container()

    item = {
        "id": f"{session_id}-{int(time.time() * 1000)}-{role}",
        "session_id": session_id,
        "role": role,
        "content": content,
        "created_at": datetime.utcnow().isoformat()
    }

    container.upsert_item(item)


@app.route(route="ask_news", auth_level=func.AuthLevel.FUNCTION, methods=["POST"])
def ask_news(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()

        question = body.get("question")
        session_id = body.get("session_id")
        chat_history = load_chat_memory(session_id)

        memory_text = ""
        for msg in chat_history:
            memory_text += f"{msg.get('role')}: {msg.get('content')}\n"

        date = body.get("date")
        timestamp = body.get("timestamp")
        top_k = int(body.get("top_k", 8))

        oa_client = get_openai_client()
        s_client = get_required_search_client()

        if not question:
            return func.HttpResponse(
                json.dumps({"error": "Missing question"}),
                status_code=400,
                mimetype="application/json"
            )

        if top_k > 20:
            top_k = 20

        emb = oa_client.embeddings.create(
            model=AZURE_OPENAI_EMBEDDING_DEPLOYMENT,
            input=question
        )

        question_vector = emb.data[0].embedding

        vector_query = VectorizedQuery(
            vector=question_vector,
            k_nearest_neighbors=top_k,
            fields="embedding"
        )

        filters = []

        if date:
            filters.append(f"date le '{date}'")

        if timestamp:
            filters.append(f"timestamp le '{timestamp}'")

        filter_text = " and ".join(filters) if filters else None

        results = s_client.search(
            search_text=question,
            vector_queries=[vector_query],
            filter=filter_text,
            select=[
                "id",
                "url",
                "date",
                "timestamp",
                "source",
                "title",
                "description",
                "content"
            ],
            top=top_k
        )

        docs = []

        for r in results:
            docs.append({
                "id": r.get("id"),
                "url": r.get("url"),
                "date": r.get("date"),
                "timestamp": r.get("timestamp"),
                "source": r.get("source"),
                "title": r.get("title"),
                "description": r.get("description"),
                "content": (r.get("content") or "")[:2500],
                "score": r.get("@search.score")
            })

        if not docs:
            return func.HttpResponse(
                json.dumps({
                    "answer": "I could not find related news in the indexed data.",
                    "sources": []
                }),
                status_code=200,
                mimetype="application/json"
            )

        context_blocks = []

        for i, doc in enumerate(docs, start=1):
            context_blocks.append(f"""
SOURCE {i}
Title: {doc.get("title")}
Date: {doc.get("date")}
Timestamp: {doc.get("timestamp")}
Source: {doc.get("source")}
URL: {doc.get("url")}

Content:
{doc.get("content")}
""")

        context = "\n\n".join(context_blocks)

        prompt = f"""
You are a news intelligence assistant.

Use the conversation memory to understand follow-up questions.
Answer using ONLY the provided news sources.

CONVERSATION MEMORY:
{memory_text}

USER QUESTION:
{question}

NEWS SOURCES:
{context}
"""

        chat = oa_client.chat.completions.create(
            model=AZURE_OPENAI_CHAT_DEPLOYMENT,
            messages=[
                {
                    "role": "system",
                    "content": "You answer using retrieved news only. Do not invent facts."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            temperature=0.2,
            max_tokens=900
        )

        answer = chat.choices[0].message.content

        save_chat_message(session_id, "user", question)
        save_chat_message(session_id, "assistant", answer)

        sources = []

        for i, doc in enumerate(docs, start=1):
            sources.append({
                "source_no": i,
                "title": doc.get("title"),
                "date": doc.get("date"),
                "timestamp": doc.get("timestamp"),
                "source": doc.get("source"),
                "url": doc.get("url"),
                "score": doc.get("score")
            })

        return func.HttpResponse(
            json.dumps({
                "question": question,
                "answer": answer,
                "sources": sources
            }, default=str),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("ask_news failed")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
@app.route(route="realtime_token", auth_level=func.AuthLevel.FUNCTION, methods=["GET"])
def realtime_token(req: func.HttpRequest) -> func.HttpResponse:
    try:
        realtime_deployment = os.getenv("AZURE_REALTIME_DEPLOYMENT", "gpt-realtime-1.5")
        realtime_voice = os.getenv("AZURE_REALTIME_VOICE", "marin")

        if not AZURE_OPENAI_ENDPOINT or not AZURE_OPENAI_KEY:
            return func.HttpResponse(
                json.dumps({"error": "Missing AZURE_OPENAI_ENDPOINT or AZURE_OPENAI_KEY"}),
                status_code=500,
                mimetype="application/json"
            )

        endpoint = AZURE_OPENAI_ENDPOINT.rstrip("/")
        url = f"{endpoint}/openai/v1/realtime/client_secrets"

        session_config = {
            "session": {
                "type": "realtime",
                "model": realtime_deployment,
                "instructions": (
                    "You are a voice news assistant for a live news globe. "
                    "Listen to the user, keep replies short, and wait while the app fetches news answers."
                ),
                "audio": {
                    "output": {
                        "voice": realtime_voice
                    }
                }
            }
        }

        r = requests.post(
            url,
            headers={
                "api-key": AZURE_OPENAI_KEY,
                "Content-Type": "application/json"
            },
            json=session_config,
            timeout=30
        )

        if r.status_code >= 400:
            return func.HttpResponse(
                json.dumps({
                    "error": "Realtime token failed",
                    "status": r.status_code,
                    "details": r.text
                }),
                status_code=500,
                mimetype="application/json"
            )

        data = r.json()

        return func.HttpResponse(
            json.dumps({
                "client_secret": data.get("value"),
                "endpoint": endpoint,
                "webrtc_url": f"{endpoint}/openai/v1/realtime/calls",
                "deployment": realtime_deployment
            }),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.exception("realtime_token failed")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
