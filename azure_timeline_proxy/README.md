# Timeline news public proxy

This anonymous Azure Functions app exposes:

- `GET /api/timeline-news?date=YYYY-MM-DD&time=HH:mm`
- `POST /api/article-details`
- `GET /api/city-news/map?since=ISO-8601-UTC`
- `GET /api/city-news/{id}`
- `POST /api/talk-news/session`
- `GET, POST, DELETE /api/news-alerts`
- `POST /api/news-alerts/test` (saved-device credentials required)

Authorized Vijaya Karnataka Bidar articles are discovered every ten minutes and sent to the `bidar-vk-articles` Service Bus queue. JSON-LD extraction is used first; Firecrawl is only a fallback when ordinary HTML is incomplete.

The protected upstream timeline key and all enrichment credentials are stored
only in Azure Function App settings. Timeline responses are cached in private
Azure Blob Storage by UTC slot.

## Required Function App settings

- `TIMELINE_NEWS_FUNCTION_KEY`: protected upstream Function key
- `AzureWebJobsStorage`: Function runtime and private Blob cache connection
- `FIRECRAWL_API_KEY`: server-side article extraction
- `AZURE_OPENAI_ENDPOINT`: Azure OpenAI resource endpoint
- `AZURE_OPENAI_KEY`: Azure OpenAI API key
- `AZURE_OPENAI_CHAT_DEPLOYMENT`: chat deployment name
- `NEWS_OPENAI_ENDPOINT`, `NEWS_OPENAI_KEY`, `NEWS_OPENAI_CHAT_DEPLOYMENT`: optional overrides used only for summaries/notification headlines, preserving other AI consumers
- `AZURE_OPENAI_REALTIME_DEPLOYMENT`: realtime deployment name (defaults to `gpt-realtime-1.5`)
- `AZURE_OPENAI_REALTIME_ENDPOINT`, `AZURE_OPENAI_REALTIME_KEY`: optional voice-only overrides for the Azure endpoint and key; use a Key Vault reference for the key in production
- `NEWS_ALERTS_COSMOS_CONTAINER`: subscription container (defaults to `news_alerts`)
- `FIREBASE_SERVICE_ACCOUNT_JSON`: FCM v1 sender credential; production uses an Azure Key Vault reference
- `FIREBASE_PROJECT_ID`: must match the mobile Firebase project (`globe-news-ecafc`)

Bidar settings:

- `BIDAR_COSMOS_ENDPOINT` and `BIDAR_COSMOS_KEY`
- `BIDAR_SERVICE_BUS_CONNECTION`
- `BIDAR_AZURE_MAPS_KEY`
- `BIDAR_SCRAPER_USER_AGENT`

The `city_news` Cosmos container is partitioned by `/city` and has a Point spatial index at `/primaryLocation/geometry/*`. Uncertain or outside-Bidar locations are retained but are not returned as globe dots.

`POST /api/talk-news/session` uses the stored Cosmos body for `bidar-vk-*`
articles. Other globe stories are extracted from their validated public HTTP(S)
article URL through server-side Firecrawl, with known timeline fields as a safe
fallback. The route validates the selected reply language and voice, then
returns a short-lived Azure client secret. The permanent Azure key and article
grounding instructions are never included in the APK.

Run tests with `python -m unittest discover -s tests -v`.

## Optional setting

- `TIMELINE_NEWS_UPSTREAM_URL`: protected timeline Function URL

Copy `local.settings.example.json` to `local.settings.json` for local
development. Never commit the populated file or expose these settings to the
Flutter application.

Area alerts are matched by a separate five-minute delivery timer against the latest cached feed, refreshed by the 15-minute timeline preloader. The backend validates either a Mapbox city/state bounding area or an optional fixed-radius subscription, groups multiple stories, enforces quiet hours and delivery limits, caches AI-refined headlines per language, and sends through FCM HTTP v1. AI enrichment failures fall back to the original headline. The mobile app requests notification permission only when the user enables an alert and does not request background location.

For the summary extraction changes, timeout safeguards, deployment requirements,
and real-device push acceptance checks, see [backend reliability](../docs/backend-reliability.md).
