# Bytebox — end-to-end checklist (Stage 10)

Two layers of evidence:

1. **Automated** — the `e2e` workflow seeds labelled demo data (`[demo-e2e]`, `e2e+…@bytebox.test`), runs the real app on Android emulators against the live backend, saves screenshots to `docs/e2e/` and `docs/store/`, then deletes the demo data. Every database rule is also covered by the SQL tests (`supabase/tests/*.sql`, run on every PR).
2. **On your phone** — the UPI payment and the ads APK install need a real device with a UPI app. Tick these once before launch.

## Automated run (emulator)

| # | Step | Expected | Evidence |
|---|---|---|---|
| 1 | First open of the **ads** build | Guest sign-in, install recorded as `ads`, consent dialog | `docs/e2e/phone-e2e-01-consent.png` |
| 2 | Explore → premium post → **Trailer** | Trailer plays for a guest (has ads access) | `docs/store/…`, `phone-e2e-02-trailer-end.png` |
| 3 | Trailer ends | "Enjoyed the trailer? Please subscribe to watch the full video" | `phone-e2e-02-trailer-end.png` |
| 4 | Subscribe → Log in → Plans | Plans with ₹49 Trial selected | `docs/store/phone-2.png` (play) / run log |
| 5 | Simulated UPI **SUCCESS** for the ₹49 order (same `report_payment_result` path the app uses) | "Payment successful! Your plan is now active." | `phone-e2e-03-payment-success.png` |
| 6 | Back from Plans | Full premium video auto-plays | `phone-e2e-04-full-video.png` |
| 7 | **Play** build, logged in | Cloud shows 15 GB + folders/files; Plans tab shows the Free account card | `docs/store/phone-1.png`, `phone-2.png` |

## On your phone (manual)

| # | Step | Expected | ✓ |
|---|---|---|---|
| M1 | Install **Bytebox-ads.apk** (from `/d`) | Opens as guest; Admin → Users shows source **ads** | ☐ |
| M2 | Play a premium post's trailer as guest | Trailer plays; end dialog asks to subscribe | ☐ |
| M3 | Subscribe → create account → **Trial ₹49** → Continue to payment | UPI chooser "Pay with" opens your UPI apps | ☐ |
| M4 | Pay ₹49 in your UPI app | Back in Bytebox: "Payment successful! Your plan is now active."; full video plays | ☐ |
| M5 | Admin → Payments → **Activated today — verify against bank** | The ₹49 order with UTR; matches your bank statement | ☐ |
| M6 | Install **Bytebox.apk** (organic) on another phone, create account, buy a plan | Admin → Requests shows the user **pending**; approve → ads content appears | ☐ |
| M7 | Admin → Plans → **Free mode ON** | App (without update) hides plans/prices; logged-in users get 15 GB; Request full access appears | ☐ |
| M8 | **Free mode OFF** | Paid plans come back immediately | ☐ |
| M9 | Settings → **Delete Account** | Account gone; Admin → Payments still shows the order (no email) | ☐ |
| M10 | Admin → Payments → **Revoke** a test payment | App shows "This payment was reversed after review…"; plan ends | ☐ |

> Tip: revoke your own ₹49 test payment afterwards (Admin → Payments) and refund yourself from the bank if you like.
