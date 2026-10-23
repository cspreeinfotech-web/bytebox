# Admin live controls — how to test each switch on a phone

Use a phone with the **direct** build installed and logged in (organic account) and, ideally, a second phone with the **ads** build (ads account). Keep the Plans screen open while you change things in the admin panel — it updates within a few seconds (Realtime), no app update or restart.

| Switch (admin) | What to do | What the phone shows |
|---|---|---|
| **Plans → edit price/duration** of Gold (e.g. ₹259 → ₹299) | Save, confirm | Gold shows ₹ 299 within seconds; if Gold was selected: "Plans were updated". Existing subscribers keep their old end date |
| Price changed while the app was showing the old price | Change price, then tap Continue on the phone before it refreshes | "Price updated to ₹X" dialog before UPI opens |
| **Plans → untick Show in app** | Save, confirm | Plan disappears; selection cleared with "Plans were updated" |
| **Payments → UPI settings → new UPI ID** | Save, confirm "New payments will go to …" | Next "Continue to payment" opens UPI with the new UPI ID/payee (an open order with the old UPI is cancelled and replaced) |
| **Payments → Clear UPI ID** (or untick Enabled) | Confirm | All plans show prices, button **Payments unavailable**, note "Payments are paused. Please try again later." |
| **Plans → Free plans: Free for organic users only** | Apply, confirm | Organic phone: prices crossed out + **FREE**, banner "Plans are free for you for a limited time", **Activate for free** → "Your Trial is active until …", Premium badge, 2 TB. Ads phone: still pays |
| Free plans: **Ads users only** / **Everyone** | Apply | Same, for that group. Switching Off → On starts a new promotion (each user can claim each plan once per promotion) |
| Plan **Free** checkbox unticked | Save | That plan stays paid even while free plans are on |
| **Free mode ON** | Turn ON, confirm | Plans hidden; Free account card (15 GB, access status, organic "Request full access") |
| As a **guest** | Tap a plan → Next / Activate | "Please log in" → log in → back on Plans with the same plan selected → continues to UPI / free activation automatically |

Every change appears in **Payments → Change history** (field, old → new, who, when).
