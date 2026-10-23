// User Choice Billing — "Pay with UPI" inside the Play build: reports the external transaction to Google
// (External Transactions API). Prepared but OFF until play_billing_enabled = true.
// Invoke with the service role (e.g. from a scheduled job) to flush pending rows.
import { createClient } from "npm:@supabase/supabase-js@2";
import { googleAccessToken, PLAY_PACKAGE } from "../_shared/google.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (req) => {
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if ((req.headers.get("authorization") ?? "") !== `Bearer ${serviceKey}`) return json(401, { error: "Service role only" });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey, { auth: { persistSession: false } });

  const { data: mode } = await admin.from("app_mode").select("play_billing_enabled").eq("id", 1).single();
  if (!mode?.play_billing_enabled) return json(200, { skipped: "play billing off" });

  const { data: rows } = await admin.from("play_external_reports")
    .select("order_id, external_transaction_id, external_transaction_token, payment_orders(amount_paise, paid_at, status)")
    .eq("status", "pending").limit(50);

  const access = await googleAccessToken();
  let reported = 0;
  for (const r of rows ?? []) {
    // deno-lint-ignore no-explicit-any
    const o = (r as any).payment_orders;
    if (!o || o.status !== "success" || !r.external_transaction_token) continue;
    const gross = Number(o.amount_paise) / 100;
    const preTax = (gross / 1.18).toFixed(2); // prices include 18% GST
    const tax = (gross - Number(preTax)).toFixed(2);
    const res = await fetch(
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PLAY_PACKAGE}/externalTransactions` +
        `?externalTransactionId=${r.external_transaction_id}`,
      {
        method: "POST",
        headers: { authorization: `Bearer ${access}`, "content-type": "application/json" },
        body: JSON.stringify({
          originalPreTaxAmount: { priceMicros: String(Math.round(Number(preTax) * 1e6)), currency: "INR" },
          originalTaxAmount: { priceMicros: String(Math.round(Number(tax) * 1e6)), currency: "INR" },
          transactionTime: o.paid_at,
          oneTimeTransaction: { externalTransactionToken: r.external_transaction_token },
          userTaxAddress: { regionCode: "IN" },
        }),
      },
    );
    const body = await res.text();
    await admin.from("play_external_reports").update(
      res.ok ? { status: "reported", reported_at: new Date().toISOString(), last_error: null }
             : { status: "failed", last_error: body.slice(0, 1000) },
    ).eq("order_id", r.order_id);
    if (res.ok) reported++;
  }
  return json(200, { reported });
});
