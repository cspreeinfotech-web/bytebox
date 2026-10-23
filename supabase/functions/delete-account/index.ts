// Deletes the calling user's account: storage objects (cloud + own channels' media),
// own channels/posts, then the auth user (rows cascade). Payment orders are kept
// (user_id becomes NULL). Refuses for the last owner.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

async function removePrefix(admin: ReturnType<typeof createClient>, bucket: string, prefix: string) {
  for (let round = 0; round < 50; round++) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, { limit: 1000 });
    if (error || !data || data.length === 0) return;
    const keys = data.filter((o) => o.id).map((o) => `${prefix}/${o.name}`);
    if (keys.length === 0) return;
    await admin.storage.from(bucket).remove(keys);
    if (data.length < 1000) return;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !who?.user) return json(401, { error: "Please log in again" });
  const uid = who.user.id;
  if (who.user.is_anonymous) return json(400, { error: "Guest accounts have nothing to delete" });

  const { data: me } = await admin.from("admins").select("role").eq("user_id", uid).maybeSingle();
  if (me?.role === "owner") {
    const { count } = await admin.from("admins").select("user_id", { count: "exact", head: true }).eq("role", "owner");
    if ((count ?? 0) <= 1) return json(409, { error: "You are the last owner. Add another owner before deleting this account." });
  }

  // Cloud files
  await removePrefix(admin, "cloud", uid);

  // Own channels → their posts' media, icons, then rows
  const { data: channels } = await admin.from("channels").select("id").eq("owner_id", uid);
  for (const ch of channels ?? []) {
    const { data: posts } = await admin.from("posts").select("id").eq("channel_id", ch.id);
    for (const p of posts ?? []) await removePrefix(admin, "media", `posts/${p.id}`);
    await removePrefix(admin, "media", `channels/${ch.id}`);
  }
  if ((channels ?? []).length) {
    await admin.from("channels").delete().in("id", channels!.map((c) => c.id));
  }
  // Posts authored in other channels
  const { data: own } = await admin.from("posts").select("id").eq("author_id", uid);
  for (const p of own ?? []) await removePrefix(admin, "media", `posts/${p.id}`);
  if ((own ?? []).length) await admin.from("posts").delete().in("id", own!.map((p) => p.id));

  const { error } = await admin.auth.admin.deleteUser(uid);
  if (error) return json(500, { error: error.message });
  return json(200, { deleted: true });
});
