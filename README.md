# Globe News

A Flutter application that presents geolocated timeline news on an interactive
native 3D Earth using `mapbox_maps_flutter`. Current app version: `1.2.0+4`.

## Features

- Native Mapbox globe projection with atmosphere and smooth idle rotation
- CARTO Dark Matter and Esri World Imagery basemaps
- GPU-rendered news dots and AI-ready pulse layers from one GeoJSON source
- IST timeline selection with 15-minute slots
- Expandable place search with smooth camera flight
- AI article summaries in English, Kannada, Hindi, and Urdu
- "Talk to News" voice interaction with bounded realtime transport
- Responsive news-detail popup with source links
- City/state news notifications with optional radius and AI-refined grouped headlines
- Firebase email/password accounts with per-user alert preferences
- One-day "Ask the news" demo with date-aware background research and citations
- Bounded HTTP clients, timeline caching, article enrichment, and retry-safe APIs
- Public Azure Functions proxy with timeline caching and article enrichment

## Repository layout

```text
lib/
  article/             Article summary models, API, state and popup
  auth/                Firebase sign-in, account gate and sign-out flow
  news_demo/           Authenticated one-day news background demo
  news_grid/           Headline grid and list presentation
  notifications/       Area alert preferences and FCM registration
  place_search/        Geocoding model, API, state and expandable search
  timeline/            Timeline models, API, state and Mapbox layers
  topic_search/        Topic search client and result presentation
  globe_widget.dart    Globe screen composition
  globe_map_controller.dart
azure_timeline_proxy/  Python Azure Functions backend
docs/                  Feature notes, deployment guidance and verification records
test/                  Unit and widget tests
```

## Requirements

- Flutter 3.38.7 or newer (stable)
- Dart 3.10.7 or newer
- Android SDK 21 or newer
- A public Mapbox access token
- A deployed instance of `azure_timeline_proxy`

Only Android platform files are currently checked into this repository. Firebase
Authentication and Cloud Messaging are configured for the Android project.

## Local configuration

Copy the safe template:

```sh
cp .env.example .env
```

On PowerShell:

```powershell
Copy-Item .env.example .env
```

Set these values in the ignored `.env` file:

```dotenv
MAPBOX_ACCESS_TOKEN=YOUR_PUBLIC_MAPBOX_TOKEN
API_BASE_URL=https://your-deployed-api.example.com
```

Run the app:

```sh
flutter pub get
flutter run --dart-define-from-file=.env
```

Never add Firecrawl, Azure OpenAI, storage connection strings, or Azure
Function keys to `.env`, Dart source, Flutter assets, or an APK.

## Backend

The public Flutter app calls:

```text
GET  /api/timeline-news?date=YYYY-MM-DD&time=HH:mm
POST /api/article-details
GET  /api/city-news/map?since=ISO-8601-UTC
GET  /api/city-news/{id}
GET, POST, DELETE /api/news-alerts
GET  /api/news-demo/status
POST /api/news-demo/ask
```

The city-news feed currently ingests the authorized Vijaya Karnataka Bidar section every ten minutes through Service Bus. Location-verified stories are merged into the existing GPU-rendered Flutter dot source, while uncertain locations remain available in the backend without an invented globe coordinate.

Area alerts use Firebase ID tokens and FCM registration. Users can select an
administrative area or a 2–250 km radius, configure language, delivery mode and
quiet hours, and send a device test from the account screen. Production FCM
delivery also requires the Azure Function App's Firebase service-account and
Cosmos settings; see [docs/accounts-and-alerts.md](docs/accounts-and-alerts.md).

The "Ask the news" demo is an authenticated, bounded retrieval experience. It
uses a server-owned request ID, a one-day activation window, shared quota and
source-linked story sections. It is intentionally a constrained demonstration,
not exhaustive historical search or a guarantee of factual completeness. See
[docs/news-demo.md](docs/news-demo.md).

The earlier full-archive topic-search prototype is disabled by default because
it requires a dedicated search index. The route returns `404` unless explicitly
enabled after the deployment gate in [docs/topic-search.md](docs/topic-search.md).

Door Drishti OCR and YouTube ingestion are intentionally deferred.

Protected upstream credentials remain in Azure Function App settings. For local
backend development, copy
`azure_timeline_proxy/local.settings.example.json` to
`azure_timeline_proxy/local.settings.json` and replace its placeholders.
`local.settings.json` is ignored by Git.

Deploy from the backend directory:

```sh
cd azure_timeline_proxy
func azure functionapp publish YOUR_FUNCTION_APP --python --build remote
```

See [azure_timeline_proxy/README.md](azure_timeline_proxy/README.md) for the
complete settings list.

## Basemaps and attribution

- Dark mode loads the CARTO Dark Matter style and reapplies globe projection,
  atmosphere, and administrative-border styling after each style change.
- Satellite mode creates a runtime Mapbox Style Specification document using
  Esri World Imagery raster tiles and CARTO administrative boundaries.

The Mapbox wordmark and attribution control remain visible as required. Source
attribution for CARTO and Esri is preserved.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

GitHub Actions runs the same checks on pushes to `main` and pull requests.

Backend tests can be run from the proxy directory with Python and `pytest`:

```sh
cd azure_timeline_proxy
python -m pytest
```

See [docs/backend-reliability.md](docs/backend-reliability.md) for the latest
deployment checks and known operational caveats.

## Security

- Runtime tokens are supplied with Dart defines and are not hardcoded.
- FCM sender credentials remain in Azure Key Vault and are resolved through the Function App managed identity.
- Nearby alerts save a selected city/state bounding area or an optional fixed radius; the app does not request background location.
- `.env`, Azure local settings, Python environments, build output, IDE files,
  Android signing keys, and service credential files are ignored.
- Article enrichment is server-side; protected keys are never shipped in the
  mobile application.

This repository does not declare an open-source license. Add an appropriate
`LICENSE` file before offering third parties permission to reuse the code.
