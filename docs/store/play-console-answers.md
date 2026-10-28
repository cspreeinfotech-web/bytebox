# Play Console answers — Bytebox (`com.bytebox.play`)

Answers match what the **Play build** actually does. Re-check before each release.

## App access
Most features work without login (guest). Cloud storage and watching videos need a free account →
**App access → All or some functionality is restricted**, add instructions:
- Email: `help.byteboxx@gmail.com` (normal organic user, confirmed, 15 GB free cloud)
- Password: *(kept outside the repo — see the owner)*
- Note: *"Open the app → Profile tab → Log in / Create account → Log in. No OTP or 2-step verification."*
- Do not delete the account or change its password while the app is in review.

## Support email (Play Console → Store settings → Contact details)
`help.byteboxx@gmail.com`

## Ads
**Does your app contain ads? → No.**

## Content rating (IARC questionnaire)
- Category: **Utility / Productivity / Communication / Other** (not a game)
- User-generated content: **Yes** — users can upload videos/photos to channels; content is moderated (channel review, reports, blocking)
- Users can interact/communicate: **No direct messaging**
- Shares user location: **No**
- Digital purchases: **No** (Play build has no purchases while `play_billing_enabled` is off; it shows no prices and hides premium videos)
- Violence / sexual content / profanity / drugs / gambling: **No** (prohibited by Community Guidelines)

## Target audience and content
- Target age group: **18 and over** only
- Appeals to children: **No**

## Data safety
| Data type | Collected | Shared | Purpose | Optional |
|---|---|---|---|---|
| Email address | Yes (when creating an account) | No | Account management | Yes |
| Name (display name) | Yes (optional, user-entered) | No | App functionality | Yes |
| User IDs (account ID) | Yes | No | App functionality, account management | No |
| Photos and videos | Yes (user uploads to cloud/channels) | No | App functionality | Yes |
| Files and docs | Yes (cloud uploads) | No | App functionality | Yes |
| App interactions (views, joins) | Yes | No | App functionality, analytics | No |
| Device or other IDs | Yes (random install ID; **no advertising ID**) | No | Fraud prevention, app functionality | No |

- Data encrypted in transit: **Yes** (HTTPS only)
- Users can request deletion: **Yes** — in app (Settings → Delete Account) and at `https://bytebox-ejim.vercel.app/delete-account`
- Committed to Play Families policy: **N/A** (18+)

> Meta Conversions API events are sent only for installs from the **website/ads APK**, not from the Play build (Play installs are organic and have no referrer).

## Advertising ID
**Does your app use advertising ID? → No.** The Play flavor removes `com.google.android.gms.permission.AD_ID` (`tools:node="remove"`), verified in CI.

## Government apps / Financial features / Health
No · No · No

## News app
No

## Account deletion URL
`https://bytebox-ejim.vercel.app/delete-account`

## Privacy policy URL
`https://bytebox-ejim.vercel.app/privacy`

## Permissions declarations
- `INTERNET` only (plus `WRITE_EXTERNAL_STORAGE` max SDK 28 for downloads on old Android). No SMS, call log, location or accessibility.

## Payments (later)
User Choice Billing (India) is **prepared but off** (`app_mode.play_billing_enabled = false`). Before enabling: enrol in the User Choice Billing programme, create one-time products with ids `bytebox_trial`, `bytebox_silver`, `bytebox_gold`, `bytebox_platinum`, `bytebox_diamond`, link a Google Cloud service account to Play Console, and set the Supabase Edge Function secret `GOOGLE_PLAY_SERVICE_ACCOUNT`. Then update the Data safety form (Purchase history).

## Release
- Upload `Bytebox-play.aab` (CI artifact **Bytebox-apks**), signed with the upload key; enrol in **Play App Signing**
- After enrolment, copy **App signing key certificate → SHA-256** into Vercel env `ANDROID_CERT_SHA256` (comma-separated with the upload key) for `assetlinks.json`
- Target API: **36 (Android 16)** — pinned in `build.gradle.kts` and checked in CI (Play requirement since 31 Aug 2026)
- 16 KB page size: native libraries aligned — checked in CI (`zipalign -P 16` + ELF segment alignment)
- versionCode = CI run number, so every new AAB can be uploaded (Play rejects a repeated versionCode)
