# Timeline news public proxy

This anonymous Azure Functions app exposes:

- `GET /api/timeline-news?date=YYYY-MM-DD&time=HH:mm`
- `POST /api/article-details`

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

## Optional setting

- `TIMELINE_NEWS_UPSTREAM_URL`: protected timeline Function URL

Copy `local.settings.example.json` to `local.settings.json` for local
development. Never commit the populated file or expose these settings to the
Flutter application.
