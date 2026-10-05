# Reliability changes (1.1.1+3)

Status: deployed successfully to `gdelt-timeline-proxy-rk2026` on 2026-10-04.
Deployment ID: `44e8698b-42ff-46ab-8c31-f0fab74ec939`.
Actual FCM test messages arrived on the Android emulator both in the foreground
and in Android's notification tray while the app was backgrounded.

Validation: 82 Flutter tests and 44 backend tests passed; Flutter analyzer found
no issues. Android release build 1.1.1+3 succeeded and was installed for testing.

Live checks after deployment:

- Current timeline: HTTP 200, 177 stories, 3.67 s (first request).
- Historical cached timeline: HTTP 200, 262 stories, 0.23 s.
- City feed: HTTP 200, 0.32 s.
- Previously failing Jerusalem Post article: real AI summaries (not excerpts),
  English in 4.22 s and Kannada in 4.61 s.
- ARY News article: generated summary rendered in the release APK.
- Device test: foreground message and background `nearby_news` notification
  observed; unauthenticated test requests rejected with HTTP 403.
- Radius/bounds matching is covered by backend tests. A newly published story
  inside the saved 10 km area was not required to trigger the explicit device test;
  observing that scheduled real-news case remains a separate acceptance check.

Evidence screenshots are in `build/verification/globe-summary-working.png`,
`globe-push-foreground.png`, and `globe-push-background.png`.

## Configuration correction

The old summary endpoint `rakesh.openai.azure.com` no longer resolved. With the
user's approval, news now reuses the existing `guardian-vision` deployment
(`gpt-4.1-mini`) in `guardian-ai-openai-617db5`. No new AI resource/deployment was
created. It shares that resource's quota and incurs normal inference usage.

Dedicated `NEWS_OPENAI_ENDPOINT`, `NEWS_OPENAI_CHAT_DEPLOYMENT`, and
`NEWS_OPENAI_KEY` settings isolate this from legacy voice/embedding settings.
The key uses the `globe-news-openai-key` Key Vault secret.

Azure previously used an FCM credential for `news-map-backend`. A new key for
the existing Firebase Admin SDK account in `globe-news-ecafc` was stored directly
in the separate `globe-news-fcm-service-account` Key Vault secret. No private key
was saved locally, no IAM role grants were added, and the old secret was retained.

The summary correction initially left legacy voice/embedding configuration
unchanged. Voice was repaired separately on 2026-10-05 as described below;
legacy embedding settings still need a separate review.

## Voice service repair (2026-10-05)

`POST /api/talk-news/session` returned HTTP 502 because the shared
`AZURE_OPENAI_ENDPOINT` still pointed at the non-resolving
`rakesh.openai.azure.com` host. The app presented this as news being unavailable
to talk about.

The existing `guardian-ai-openai-617db5` resource now has a
`globe-news-realtime` deployment of `gpt-realtime-1.5` version `2026-02-23`,
using GlobalStandard capacity 1. Normal Azure inference usage is billable.
Voice uses `AZURE_OPENAI_REALTIME_ENDPOINT` and `AZURE_OPENAI_REALTIME_KEY`;
the key reuses the existing `globe-news-openai-key` Key Vault reference.
`AZURE_OPENAI_REALTIME_DEPLOYMENT` selects `globe-news-realtime`. These overrides
leave the summary and legacy embedding settings unchanged. Older installations
can still fall back to `AZURE_OPENAI_ENDPOINT` and `AZURE_OPENAI_KEY`.

Backend deployment `b7e010f0-fc4b-4d9f-8d5e-b6cd0fab75b1` succeeded. Post-deployment
function requests temporarily stalled; the function app was stopped and started,
and subsequent live checks succeeded. Verification:

- All 82 backend tests passed, including voice override/fallback coverage.
- Public voice session creation returned HTTP 200.
- Azure WebRTC negotiation returned HTTP 201 and the data channel connected.
- A real Jerusalem Post article produced an article-specific spoken response:
  both the completed transcript and incoming audio were received.
- The existing news-demo status route also returned HTTP 200 after recovery.

The desktop WebRTC check follows the app's token/SDP/data-channel flow; physical
Android microphone and speaker routing were not tested. No APK update is needed.
Azure's `webrtcfilter=on` omits `response.done`; verification must wait for
`response.output_audio_transcript.done`, which the mobile app already handles.

## Changes

- Cached timeline reads no longer call Azure Search or write blobs. Enrichment
  runs in the preloader. Historical reads cannot replace `latest.json`.
- Storage/Cosmos clients reuse connections and have bounded timeouts/retries.
  Failed cache writes do not turn successful upstream news into errors, and
  HTTP errors use `Cache-Control: no-store`.
- Mobile requests abort on timeout, retry transient news/registration failures
  once, and give the optional city feed only three seconds. Saved area preferences
  open while notification registration reconnects in the background.
- Article extraction tries ordinary public HTML/JSON-LD first, then Firecrawl.
  Direct requests pin a public IP, verify HTTPS hostname certificates, revalidate
  redirects, and limit download size/time. Blocked/premium content is not bypassed.
- Summary requests use `max_completion_tokens`, omit optional temperature, accept
  the alternative Azure key/deployment environment names, and cache successful
  results by URL/language. See the official OpenAI Chat Completions reference:
  https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create
- If AI fails after text extraction, the response contains a clearly marked
  original-language **source excerpt**, not a fabricated summary or translation.
- AI headline failures no longer prevent FCM delivery. A separate monitored
  five-minute timer processes the latest cached feed even if a new preload fails.
- Firebase sender project must match `FIREBASE_PROJECT_ID`, defaulting to
  `globe-news-ecafc`. FCM access tokens are reused until refresh is needed.
- The account screen has **Send test notification**. The server authenticates
  the installation ID/device secret, sends only to that saved device, and applies
  a one-minute cooldown. FCM acceptance is not represented as device receipt;
  a matching test ID received by the app is needed for the verified message.

## Deployment prerequisites

Keep all existing app settings. Verify these in Azure Function App environment
variables / Key Vault references; never put private credentials in the APK:

- `AzureWebJobsStorage`, `TIMELINE_NEWS_FUNCTION_KEY`, and Cosmos settings.
- `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_KEY` (or `AZURE_OPENAI_API_KEY`), and
  `AZURE_OPENAI_CHAT_DEPLOYMENT` (or `AZURE_OPENAI_DEPLOYMENT_NAME`). The deployment
  must support Chat Completions JSON mode. Excerpts alone do not verify AI access.
  The scoped `NEWS_OPENAI_*` settings above take precedence for summaries and
  notification headlines on this deployment.
- `FIRECRAWL_API_KEY` for publishers without usable ordinary HTML.
- `FIREBASE_PROJECT_ID=globe-news-ecafc` and `FIREBASE_SERVICE_ACCOUNT_JSON` referencing
  a service account from that project with FCM send permission. The HTTP v1 FCM
  API must be enabled. Do not paste the service-account JSON into chat.

With Azure CLI and Azure Functions Core Tools installed and signed in:

```powershell
az login
cd azure_timeline_proxy
func azure functionapp publish gdelt-timeline-proxy-rk2026 --python
```

This must publish the whole backend directory, including the new helper modules.
Do not upload local settings, local Python environments, or Windows dependencies.

## Acceptance checks after deployment

1. Confirm both `preload_latest_timeline` and `deliver_cached_news_alerts` are
   indexed/running in Azure; check their logs without exposing credential values.
2. Open the previously failing Jerusalem Post article. Confirm either a real AI
   summary or an explicitly labeled excerpt; verify translated summaries separately.
3. Repeatedly load the current and historical timeline; inspect response latency
   and check that no errors have been cached.
4. Install 1.1.1+3, sign in, choose an area/radius and grant notifications.
5. Tap **Send test notification** with the app open, then again with the app in the
   background (wait one minute between tests). Observe the actual notification.
6. Observe a real new story inside the selected radius and verify outside-radius
   stories do not trigger that subscription. A test push does not prove filtering.

Local regression tests cover timeouts, cancellation, optional city-feed failures,
source extraction/SSRF guards, summary fallback labeling, cache reads/writes,
Firebase project mismatch, test-device authentication, and AI-independent FCM sends.
Live public extraction succeeded for sampled Jerusalem Post and iHeart stories;
another sampled publisher needed the fallback extractor. Publisher access rules,
service outages, quota, and Android notification permissions can still affect
individual articles or deliveries; the observed successes are not an uptime SLA.
