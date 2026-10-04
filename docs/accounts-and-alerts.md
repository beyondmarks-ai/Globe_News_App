# Accounts and area alerts

Update: backend reliability fixes were deployed on 2026-10-04, and actual test
pushes reached Android in both foreground and background. See
[deployment verification](backend-reliability.md) for configuration, timings,
and remaining acceptance-check scope. The earlier findings below are historical.

The Android app uses Firebase Authentication email/password accounts in
`globe-news-ecafc`. Passwords are handled by Firebase Authentication, never saved
in app preferences or sent to the Azure news API. Email/password sign-in is
enabled in the project. To provision it again, run:

```powershell
firebase deploy --only auth --project globe-news-ecafc
```

Sign-up is followed by area selection. Search for a city, district, or state and
choose its administrative bounds or a radius of 2, 5, 10, 25, 50, 100, or 250 km.
One area is active per device. Preferences (including the full city/state label,
language, delivery mode, and quiet hours) are stored separately for each Firebase
user on that device. They do not yet sync between devices.

Enabling alerts requests Android notification permission, obtains an FCM token,
and sends the selected coordinates and coverage to `POST /api/news-alerts`.
Success is shown only after the server acknowledges registration. A denied
permission or failed request offers a retry; users can explicitly save their area
with notifications off. Token changes re-register the active preference.

The account icon on the globe opens account details, news preferences, and sign-out.
Signing out removes this device's server registration before ending the Firebase
session, while retaining the user's local preferences for their next sign-in.
If removing the registration fails, sign-out displays an error and can be retried.
Previously enabled alerts are re-registered on the next sign-in if permission is
still granted. Anonymous legacy subscriptions are retired before onboarding.

The Azure service already matches news to bounds/radius and applies quiet hours
and delivery limits. Production delivery requires its `FIREBASE_SERVICE_ACCOUNT_JSON`
setting to reference a credential for **globe-news-ecafc**, plus the configured
Cosmos notification container and timeline processor. An accepted subscription
alone does not prove that Azure can send FCM messages; verify a matching new story
arrives on a physical device. No service-account private key belongs in the APK.

Build with both `API_BASE_URL` and a public `MAPBOX_ACCESS_TOKEN` in ignored `.env`:

```powershell
flutter build apk --release --dart-define-from-file=.env
```

## Verification (2026-10-04)

- Release APK 1.1.0+2 built; 74 Flutter tests and 7 backend tests passed.
- Flutter analyzer reported no issues.
- Live Firebase test-account creation and password sign-in succeeded.
- Release APK sign-in, Bengaluru city search, 10 km selection, Android permission,
  and initial server registration succeeded. The account screen showed the full
  city/state label and active alerts; the globe opened.
- Sign-out succeeded on retry after an initial unregister failure. Signing in
  again restored the area/radius, but automatic alert re-registration failed and
  correctly displayed a reconnect warning. Notification connectivity is therefore
  not yet consistently verified in this environment.
- Actual FCM delivery was not observed; verify the Azure sender configuration
  and a matching new story on a physical device before claiming delivery works.
- A later timeline request returned HTTP 503 from the deployed API. Backend
  availability needs investigation before treating the whole app as verified.
- The temporary Firebase test account and local credential fixture were removed.
