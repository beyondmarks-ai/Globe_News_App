# One-day news background demo

## User flow

The new **Ask the news · 1-day demo** button opens a text conversation. A question
retrieves up to five date-aware web/news search results, identifies the event, then
retrieves up to five background results about that issue. An ambiguous question
can return a clarification instead of searching unrelated historical events.

The response tells a chronological story when the evidence supports it:
**How it began → How it developed → The event you asked about → Responses and
what happened next → Where things stand**. It explains the underlying policy or
dispute, key actors, demands, allegations and available official responses. Later
developments must have their own dates, not be merged into the requested event.
Missing origins or outcomes are identified as gaps, not invented to complete a
story. It provides source links and labels uncertainty. Follow-ups refer to a server-owned
previous answer ID, scoped to the current Firebase user. Previous answers are
context, not evidence for new claims.

The backend reads at most **three public articles** (one event report and two
background reports), using the existing public-IP-validated, bounded HTML reader.
Social-media pages are not selected for article reading. Blocked publishers fall
back to their search excerpts without bypassing restrictions or paid scraping.
Up to 3,000 characters of verbatim passages per readable article are selected in
original order. This is **not complete article or historical coverage**.
The event search retains explicit dates without a past-24-hour filter; questions
about today/latest include the current India date. Search relevance is not proof
of event date. Publication dates and event dates can differ or be unavailable.
When an English/ISO event date is available, the background query adds a
`before:YYYY-MM-DD` hint to seek earlier reporting. Major social/video domains
are excluded through search operators. These are retrieval hints, not guarantees
of publisher quality or verified event dates; the evidence still governs answers.
No voice is added to this demo. Every story section selects specific source-passage
IDs from a strict enumeration. These resolve to verbatim source paragraphs; the AI
does not retype quotations. The backend derives publisher citations from the
selected passages and omits sections with missing/unknown IDs, with a visible notice.
Search snippets are cleaned of image/link markup and block-page noise before use.
AI output can still make mistakes: valid passage IDs do not prove semantic
entailment of the generated narrative.

## Server-enforced limits

- Fixed 24-hour window from `NEWS_DEMO_STARTS_AT` in UTC; no client-controlled clock.
- Only Firebase accounts created during that window with verified email qualify.
  Firebase accounts:lookup validates the ID token, project, registration time and
  email verification. Existing pre-demo accounts do not qualify.
- 100 accepted question attempts **shared across all users**, including follow-ups,
  clarifications and provider failures. Authentication/validation/busy rejections
  do not consume an attempt.
- One active request at a time, followed by a shared 60-second cooldown to protect
  the existing deployment's 10,000-token/minute quota. Busy/cooldown rejections
  consume no question. No automatic paid-call retries.
- Two Firecrawl search requests maximum per attempt, five results each, no paid
  scraping or premium proxy options. Normally up to four search credits/attempt,
  or 400 credits across the 100-attempt window.
- Two existing Azure AI calls maximum per attempt: a 350-token event-selection
  response and a 1,600-token story including supporting passage IDs. Search excerpts are capped at 800 characters
  per source; at most three are replaced by 3,000-character article passages.
  Previous-answer context is compacted (all five headings retained, 240 characters
  each), and planning excerpts are capped at 500 characters each. URLs are not sent
  to the model. Questions, excerpts and context are bounded.
- Blob ETag compare-and-swap reserves each attempt before any paid work. Request
  IDs are bound to user and payload; replay returns saved output or processing
  status without more provider calls. A crashed/failed attempt is not refunded.
- The expiry gate runs before authentication, reservation, and each provider call.
  Already-started provider requests can finish shortly after expiry; no new ones
  start after it. No scheduler is needed to stop demo search usage.

The limits cap application requests, not the Azure invoice in rupees. The demo
uses existing Firecrawl credits and the existing Azure AI resource. No search
subscription or new billable Azure resource is provisioned. Existing application
hosting, storage, unrelated timers and other features continue normally.

## Configuration and operation

Required settings on `gdelt-timeline-proxy-rk2026`:

- `NEWS_DEMO_ENABLED=true`
- `NEWS_DEMO_STARTS_AT=<ISO8601 UTC activation time>`
- `FIREBASE_WEB_API_KEY=<public API key for globe-news-ecafc>`
- Existing `FIRECRAWL_API_KEY` and `NEWS_OPENAI_*` credentials remain server-only.

`GET /api/news-demo/status` returns public window/quota status, without user data.
`POST /api/news-demo/ask` requires a Firebase bearer token and a JSON body with
`question`, a random 32-hex-character `requestId`, and optional `previousId`.
The app sends verification emails through Firebase and refreshes the token on retry.

To stop early, set `NEWS_DEMO_ENABLED=false` with Azure CLI. **Do not change
`NEWS_DEMO_STARTS_AT` to extend or reset the quota without fresh approval.** The
operator helper preserves an already active window.

State is stored under `timeline-news-cache/news-demo/<activation>/state.json`.
It contains user IDs, request hashes, source-linked results and processing status;
no passwords, Firebase tokens or provider credentials. State is retained after
expiry for idempotency/audit; there is no automatic deletion policy in this demo.
The UI warns users not to include confidential information in questions sent to
Firecrawl and Azure AI.

The abandoned full-archive prototype is disabled with `NEWS_ARCHIVE_ENABLED=false`.
Its HTTP route returns 404 and its timer does no indexing. It must not be enabled
without addressing the documented capacity limit in [topic-search.md](topic-search.md).

## Verification

Backend tests cover atomic concurrent quota reservation, idempotency, ownership,
old/new registration eligibility, verified-email checks, expiry, disabled mode,
bounded provider requests, citation-ID validation, clarifications and failures.
Story regression tests also cover exact-date query preservation, five ordered
sections, background-focused queries, bounded public reading, publisher failure,
duplicate URLs, passage selection and expired-demo blocking of article reads.
Flutter tests cover authenticated requests, error codes, request IDs, conversation
context, all five story sections, email-verification retries and small-screen layout.

Official API references used:

- [Firecrawl search and credit usage](https://docs.firecrawl.dev/features/search)
- [OpenAI Chat Completions structured response formats](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)

Backend deployment succeeded on 2026-10-04. Final deployment ID:
`315e8551-afe3-417c-9d4c-0c5c48d470ac` (includes compact context and quota cooldown).
The demo was initially staged disabled during the first APK build.
All 96 Flutter and 66 backend tests passed;
Flutter analyzer reported no issues. Live provider checks returned recent and
historical source links and a source-cited explanation in approximately 16 seconds.

## Activation and final live results

- Starts: **2026-10-04 14:51:25 IST** (`2026-10-04T09:21:25.721540Z`).
- Ends: **2026-10-05 14:51:25 IST** (`2026-10-05T09:21:25.721540Z`).
- 94 accepted question attempts remained at final verification; six were used in
  verification (five completed, one failed). Busy/verification-email rejections and
  duplicate replays did not consume additional attempts. No quota/window reset.
- New unverified Firebase account: HTTP 403 `verify_email`; the same synthetic
  account, after administrative verification, received a cited explanation.
- Live initial question and follow-up: HTTP 200 with current/background source
  links. The final initial request took approximately 61 seconds. Earlier live
  initial requests ranged from approximately 27 to 66 seconds.
- Immediate follow-up was rejected with HTTP 429 `busy`, without reserving an
  attempt. The same request ID succeeded after the 60-second cooldown.
- Replaying a completed request returned its saved result with no additional
  provider work or quota consumption.
- All synthetic Firebase test accounts were deleted; existing accounts untouched.
- APK 1.2.0+4 built successfully (approximately 149 MB). Android install and launch
  verified; conversation UI covered by widget tests and backend by live REST
  tests. Full conversation entry in the installed APK and real email-inbox
  verification delivery were not independently exercised.

There were intermittent gateway/non-JSON responses and connection timeouts during
verification. The app exposes **Check same request** for safe recovery, and errors
remain bounded. This is a constrained demo, not a production availability promise.
The successful end-to-end REST follow-up followed deployment of the shared
cooldown; do not claim the cooldown eliminates unrelated gateway outages.

## Story-history update — 4 October 2026

Deployed backend revision `027909b8-e98b-4ec2-b7b5-46aded550eac` (Azure deployment
status 4, complete). The current 1.2.0+4 APK already renders arbitrary response
sections: no app rebuild or reinstall is needed. Submit a **new question** to use
the new backend; idempotent replays intentionally retain their original answers.

- 80 backend tests and 97 Flutter tests passed (177 total); Flutter analyzer clean.
- The final live REST question was: “What happened at the Jantar Mantar protest on
  2 October 2026, and why did it happen?” It returned HTTP 200 in **16.6 seconds**,
  with all five story headings and source links. Earlier-report retrieval included
  24 September reporting on the resignation demand and ultimatum.
- Request ID: `0aba3abc1d2b4381d0ff5f63a0f747f0`. **85 shared attempts remained**.
  The original start/end timestamps and 100-attempt limit were unchanged.
- The answer explicitly reported missing evidence about the final resolution.
  This is a bounded search demonstration, not proof of exhaustive history or
  claim-by-claim factual accuracy. Search providers can still return off-date or
  excluded-domain results; search operators are hints, not security boundaries.
- Earlier test iterations found thin history, event-date/location mixing,
  unnecessary clarification and brittle AI-retyped quotations. The final approach
  uses pre-event background hints, specific passage IDs, and paragraph-level
  attribution. One local test was interrupted by a network outage; its synthetic
  account was subsequently removed and its reservation marked failed without refund.
  All synthetic accounts created for these checks have been deleted.
- The five-section layout was verified in Flutter widget tests; live content was
  tested through the authenticated backend, not manually entered on the emulator.

The OpenAI Docs guidance on structured-output errors informed passage-ID validation
and explicit missing-evidence handling. Schema correctness does not establish
factual entailment: [official guidance](https://developers.openai.com/api/docs/guides/structured-outputs).
