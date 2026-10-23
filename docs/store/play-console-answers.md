# Play Console answers — Bytebox (`com.bytebox.play`)

Answers match what the **Play build** actually does. Re-check before each release.

## App access
Most features work without login (guest). Cloud storage needs a free account → provide reviewer credentials:
create an account in the app (e.g. `playreview@<your-domain>`) and enter it under **App access → All or some functionality is restricted**.

## Ads
**Does your app contain ads? → No.**

## Content rating (IARC questionnaire)
- Category: **Utility / Productivity / Communication / Other** (not a game)
- User-generated content: **Yes** — users can upload videos/photos to channels; content is moderated (channel review, reports, blocking)
- Users can interact/communicate: **No direct messaging**
- Shares user location: **No**
- Digital purchases: **No** (Play build has no purchases while `play_billing_enabled` is off)
- Violence / sexual content / profanity / drugs / gambling: **No** (prohibited by Community Guidelines)

## Target audience and content
- Target age group: **18 and over** only
- Appeals to children: **No**

## Data safety
| Data type | Collected | Shared | Purpose | Optional |
|---|---|---|---|---|
| Email address | Yes (when creating an account) | No | Account management | Yes |
| User IDs (account ID) | Yes | No | App functionality, account management | No |
| Photos and videos | Yes (user uploads to cloud/channels) | No | App functionality | Yes |
| Files and docs | Yes (cloud uploads) | No | App functionality | Yes |
| App interactions (views, joins) | Yes | No | App functionality, analytics | No |
| Device or other IDs | Yes (random install ID; **no advertising ID**) | No | Fraud prevention, app functionality | No |

- Data encrypted in transit: **Yes** (HTTPS only)
- Users can request deletion: **Yes** — in app (Settings → Delete Account) and at `https://<vercel-domain>/delete-account`
- Committed to Play Families policy: **N/A** (18+)

> Meta Conversions API events are sent only for installs from the **website/ads APK**, not from the Play build (Play installs are organic and have no referrer).

## Advertising ID
**Does your app use advertising ID? → No.** The Play flavor removes `com.google.android.gms.permission.AD_ID` (`tools:node="remove"`), verified in CI.

## Government apps / Financial features / Health
No · No · No

## News app
No

## Account deletion URL
`https://<vercel-domain>/delete-account`

## Permissions declarations
- `INTERNET` only (plus `WRITE_EXTERNAL_STORAGE` max SDK 28 for downloads on old Android). No SMS, call log, location or accessibility.

## Payments (later)
User Choice Billing (India) is **prepared but off** (`app_mode.play_billing_enabled = false`). Before enabling: enrol in the User Choice Billing programme, create one-time products with ids `bytebox_trial`, `bytebox_silver`, `bytebox_gold`, `bytebox_platinum`, `bytebox_diamond`, link a Google Cloud service account to Play Console, and set the Supabase Edge Function secret `GOOGLE_PLAY_SERVICE_ACCOUNT`. Then update the Data safety form (Purchase history).

## Release
- Upload `Bytebox-play.aab` (CI artifact **Bytebox-apks**), signed with the upload key; enrol in **Play App Signing**
- After enrolment, copy **App signing key certificate → SHA-256** into Vercel env `ANDROID_CERT_SHA256` (comma-separated with the upload key) for `assetlinks.json`
- Target API: latest (from Flutter); 16 KB page size supported
