// User Choice Billing — "Pay with Google Play": verifies a purchase token with Google, then activates.
// Prepared but OFF until app_mode.play_billing_enabled = true and GOOGLE_PLAY_SERVICE_ACCOUNT is set.
import { createClient } from "npm:@supabase/supabase-js@2";
import { googleAccessToken, PLAY_PACKAGE } from "../_shared/google.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who } = await admin.auth.getUser(token);
  if (!who?.user || who.user.is_anonymous) return json(401, { error: "Please log in" });

  const { data: mode } = await admin.from("app_mode").select("play_billing_enabled").eq("id", 1).single();
  if (!mode?.play_billing_enabled) return json(503, { error: "Google Play billing is not enabled" });

  const { product_id, purchase_token } = await req.json().catch(() => ({}));
  if (!product_id || !purchase_token) return json(400, { error: "product_id and purchase_token are required" });

  try {
    const access = await googleAccessToken();
    const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PLAY_PACKAGE}` +
      `/purchases/products/${encodeURIComponent(product_id)}/tokens/${encodeURIComponent(purchase_token)}`;
    const res = await fetch(url, { headers: { authorization: `Bearer ${access}` } });
    const purchase = await res.json();
    if (!res.ok) return json(502, { error: "Google verification failed", details: purchase });
    if (purchase.purchaseState !== 0) return json(409, { error: "Purchase is not completed", state: purchase.purchaseState });

    const { data, error } = await admin.rpc("play_activate", {
      p_user_id: who.user.id, p_product_id: product_id, p_purchase_token: purchase_token,
      p_google_order_id: purchase.orderId ?? null, p_raw: purchase,
    });
    if (error) return json(422, { error: error.message });

    // Consume so the same one-time product can be bought again later.
    await fetch(`${url}:consume`, { method: "POST", headers: { authorization: `Bearer ${access}` } });
    return json(200, { status: data });
  } catch (e) {
    return json(500, { error: (e as Error).message });
  }
});
