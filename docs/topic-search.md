# Topic search implementation status

Update: the selected client demo is now on-demand news/background retrieval,
not full-archive indexing. See [news-demo.md](news-demo.md). The archive prototype
is explicitly disabled unless `NEWS_ARCHIVE_ENABLED=true`; the APK's entry point
now opens the one-day demo instead of this earlier archive-search screen.

The Flutter topic-search screen is implemented locally, with an Any time default,
relevance/newest-observed sorting, pagination, request cancellation, error states,
and the existing article-summary popup. It searches independently of the globe's
selected date. Local version is 1.2.0+4; no replacement APK has been built yet.

Validation: 90 Flutter tests and 54 backend tests pass. Flutter analyzer is clean.

## Deployment gate (2026-10-04)

This feature is **not deployed**. The running backend and previously delivered
1.1.1 APK are unchanged.

The configured `gdelt-news-search.search.windows.net` endpoint does not resolve,
and Azure CLI found no Azure AI Search services in the current subscription.
The retained timeline cache contains 4,808 snapshots totaling 1,064,063,719 bytes.
An isolated Blob/SQLite prototype indexed 288 snapshots into 128,230 distinct
articles (104,873,984 bytes). This demonstrates that a 128 MiB in-memory archive
cannot cover the retained collection. Do not deploy this prototype's indexer as
the production solution for the full archive.

Prototype blobs are under `timeline-news-cache/topic-search/`; no timeline
snapshots, user accounts, or existing application settings were modified.
The archive's backfill-complete flag remains false, and the UI labels incomplete
coverage. No paid Azure resource was created.

Recommended next step: obtain approval for a dedicated Azure AI Search service,
then replace the prototype storage adapter with managed indexing, backfill retained
snapshots, verify search and paging against the live endpoint, and build/test the
new APK. Preserve explicit coverage disclosure and URL-based deduplication.

Azure's Retail Prices API lists the Southeast Asia Basic unit at USD 0.101/hour
(about USD 73.73 for 730 hours), before taxes, currency conversion, and any other
usage. This is one search unit, not a high-availability multi-replica deployment.
Additional replicas or higher tiers require separate cost approval.

The existing AI resource can summarize articles, but it does not replace a
search index. Initial topic matching uses safe keyword normalization and a small
synonym set; it is not unrestricted conversational or semantic search. Archive
dates mean first observed, not verified publication dates. Search covers saved
headlines, URL keywords, and locations, not the full text of all published news.
