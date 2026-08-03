# Globe News

A Flutter application that presents geolocated timeline news on an interactive
native 3D Earth using `mapbox_maps_flutter`.

## Features

- Native Mapbox globe projection with atmosphere and smooth idle rotation
- CARTO Dark Matter and Esri World Imagery basemaps
- GPU-rendered news dots and AI-ready pulse layers from one GeoJSON source
- IST timeline selection with 15-minute slots
- Expandable place search with smooth camera flight
- AI article summaries in English, Kannada, Hindi, and Urdu
- Responsive news-detail popup with source links
- City/state news notifications with optional radius and AI-refined grouped headlines
- Public Azure Functions proxy with timeline caching and article enrichment

## Repository layout

```text
lib/
  article/             Article summary models, API, state and popup
  place_search/        Geocoding model, API, state and expandable search
  timeline/            Timeline models, API, state and Mapbox layers
  globe_widget.dart    Globe screen composition
  globe_map_controller.dart
azure_timeline_proxy/  Python Azure Functions backend
test/                  Unit and widget tests
```

## Requirements

- Flutter 3.38.7 (stable) with Dart 3.10.7
- Android SDK 21 or newer
- A public Mapbox access token
- A deployed instance of `azure_timeline_proxy`

Only Android platform files are currently checked into this repository.

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
```

The city-news feed currently ingests the authorized Vijaya Karnataka Bidar section every ten minutes through Service Bus. Location-verified stories are merged into the existing GPU-rendered Flutter dot source, while uncertain locations remain available in the backend without an invented globe coordinate.

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
