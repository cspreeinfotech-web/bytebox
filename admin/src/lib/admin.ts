import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type Counters = { approvals: number; requests: number | null; payments: number | null; reports: number; role: "owner" | "content" };

/** Loads the signed-in admin; redirects when not signed in or not an admin. */
export async function requireAdmin(opts: { owner?: boolean } = {}) {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) redirect("/admin/login");
  const { data: counters } = await supabase.rpc("admin_counters");
  if (!counters) redirect("/admin/login?err=This account is not an admin.");
  const c = counters as Counters;
  if (opts.owner && c.role !== "owner") redirect("/admin?err=Only the owner can open that page.");
  return { supabase, user: auth.user, counters: c };
}

export type SP = Promise<Record<string, string | string[] | undefined>>;
export const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";

/** Redirect back with a flash message. */
export function back(path: string, msg: { ok?: string; err?: string }): never {
  const q = new URLSearchParams();
  if (msg.ok) q.set("ok", msg.ok);
  if (msg.err) q.set("err", msg.err);
  redirect(`${path}${path.includes("?") ? "&" : "?"}${q.toString()}`);
}
