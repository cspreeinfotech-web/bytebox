// Bank / payment-provider alert → activates an order by reference.
// Prepared but inactive until the secret UPI_WEBHOOK_SECRET is set:
//   supabase secrets set UPI_WEBHOOK_SECRET=<long random string>
// Provider must POST JSON {"reference","utr","amount_paise"} with header
//   x-signature: hex(HMAC_SHA256(UPI_WEBHOOK_SECRET, raw body))
import { createClient } from "npm:@supabase/supabase-js@2";
import { hmacHex, safeEqual } from "../_shared/hmac.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const secret = Deno.env.get("UPI_WEBHOOK_SECRET");
  if (!secret) return json(503, { error: "webhook_not_configured" });

  const raw = await req.text();
  const given = (req.headers.get("x-signature") ?? "").toLowerCase();
  if (!given || !safeEqual(given, await hmacHex(secret, raw))) return json(401, { error: "bad_signature" });

  let payload: { reference?: string; utr?: string; amount_paise?: number };
  try {
    payload = JSON.parse(raw);
  } catch {
    return json(400, { error: "bad_json" });
  }
  const { reference, utr, amount_paise } = payload;
  if (!reference || !utr || typeof amount_paise !== "number") return json(400, { error: "missing_fields" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data, error } = await admin.rpc("webhook_payment", {
    p_reference: reference, p_utr: utr, p_amount_paise: amount_paise,
  });
  if (error) return json(422, { error: error.message });
  return json(200, { status: data });
});
