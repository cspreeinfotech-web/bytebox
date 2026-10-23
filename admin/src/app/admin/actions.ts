"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { back } from "@/lib/admin";
import { createClient } from "@/lib/supabase/server";

const s = (f: FormData, k: string) => String(f.get(k) ?? "").trim();

async function rpc(path: string, fn: string, args: Record<string, unknown>, ok: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc(fn, args);
  if (error) back(path, { err: error.message });
  revalidatePath("/admin", "layout");
  back(path, { ok });
}

// ---------------- auth
export async function signIn(form: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email: s(form, "email"), password: s(form, "password") });
  if (error) back("/admin/login", { err: error.message });
  redirect("/admin");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/admin/login");
}

// ---------------- channels
export async function reviewChannel(form: FormData) {
  const approve = s(form, "decision") === "approve";
  await rpc("/admin/approvals", "admin_review_channel", {
    p_channel_id: s(form, "id"), p_approve: approve, p_audience: s(form, "audience") || "all",
    p_reason: s(form, "reason") || null,
  }, approve ? "Channel approved and published." : "Channel rejected.");
}

export async function createChannel(form: FormData) {
  const tags = s(form, "tags").split(",").map((t) => t.trim()).filter(Boolean);
  await rpc("/admin/channels", "admin_create_channel", {
    p_name: s(form, "name"), p_category: s(form, "category"), p_description: s(form, "description"),
    p_tags: tags, p_audience: s(form, "audience") || "all",
  }, "Channel created (approved).");
}

export async function updateChannel(form: FormData) {
  await rpc("/admin/channels", "admin_update_channel", {
    p_channel_id: s(form, "id"), p_audience: s(form, "audience"), p_publish_state: s(form, "publish_state"),
  }, "Channel updated.");
}

export async function deleteChannel(form: FormData) {
  const supabase = await createClient();
  const id = s(form, "id");
  const { data: posts } = await supabase.from("posts").select("id").eq("channel_id", id);
  const keys: string[] = [];
  for (const p of posts ?? []) {
    const { data } = await supabase.storage.from("media").list(`posts/${p.id}`);
    for (const o of data ?? []) keys.push(`posts/${p.id}/${o.name}`);
  }
  const { data: icons } = await supabase.storage.from("media").list(`channels/${id}`);
  for (const o of icons ?? []) keys.push(`channels/${id}/${o.name}`);
  if (keys.length) await supabase.storage.from("media").remove(keys);
  await rpc("/admin/channels", "delete_channel", { p_channel_id: id }, "Channel deleted.");
}

// ---------------- posts + reports
export async function updatePost(form: FormData) {
  await rpc("/admin/posts", "admin_set_post", {
    p_post_id: s(form, "id"), p_status: s(form, "status"), p_audience: s(form, "audience"),
    p_is_premium: s(form, "is_premium") === "on",
  }, "Post updated.");
}

export async function deletePost(form: FormData) {
  const supabase = await createClient();
  const id = s(form, "id");
  const { data } = await supabase.storage.from("media").list(`posts/${id}`);
  const keys = (data ?? []).map((o) => `posts/${id}/${o.name}`);
  if (keys.length) await supabase.storage.from("media").remove(keys);
  await rpc("/admin/posts", "delete_post", { p_post_id: id }, "Post deleted.");
}

export async function handleReport(form: FormData) {
  await rpc("/admin/posts?tab=reports", "admin_handle_report", {
    p_report_id: Number(s(form, "id")), p_status: s(form, "status"),
  }, "Report updated.");
}

// ---------------- payments
export async function markPaid(form: FormData) {
  await rpc(`/admin/payments?filter=${s(form, "filter") || "all"}`, "admin_mark_paid",
    { p_order_id: s(form, "id"), p_utr: s(form, "utr") }, "Payment marked as paid; plan activated.");
}

export async function revokePayment(form: FormData) {
  await rpc(`/admin/payments?filter=${s(form, "filter") || "all"}`, "admin_revoke_payment",
    { p_order_id: s(form, "id"), p_reason: s(form, "reason") }, "Payment reversed; plan ended and transaction id blocked.");
}

// ---------------- users / requests
export async function setAccess(form: FormData) {
  const path = s(form, "back") || "/admin/requests";
  await rpc(path, "admin_set_access", { p_user_id: s(form, "id"), p_status: s(form, "status") },
    s(form, "status") === "approved" ? "Full access approved." : "Access updated.");
}

// ---------------- plans + modes
export async function toggleFreeMode(form: FormData) {
  const supabase = await createClient();
  const on = s(form, "free_mode") === "on";
  const { error } = await supabase.from("app_mode").update({ free_mode: on, updated_at: new Date().toISOString() }).eq("id", 1);
  if (error) back("/admin/plans", { err: error.message });
  revalidatePath("/admin", "layout");
  back("/admin/plans", { ok: on ? "Free mode is ON — no plans or prices in the app." : "Free mode is OFF — paid plans are back." });
}

function planFields(form: FormData) {
  return {
    name: s(form, "name"),
    price_inr: Number(s(form, "price_inr")),
    duration_days: Number(s(form, "duration_days")),
    perks: s(form, "perks").split("\n").map((p) => p.trim()).filter(Boolean),
    badge: s(form, "badge") || null,
    position: Number(s(form, "position") || 0),
    active: s(form, "active") === "on",
    updated_at: new Date().toISOString(),
  };
}

export async function savePlan(form: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("plans").update(planFields(form)).eq("id", Number(s(form, "id")));
  if (error) back("/admin/plans", { err: error.message });
  revalidatePath("/admin/plans");
  back("/admin/plans", { ok: "Plan saved. The app updates live." });
}

export async function addPlan(form: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("plans").insert({ code: s(form, "code").toLowerCase(), ...planFields(form) });
  if (error) back("/admin/plans", { err: error.message });
  revalidatePath("/admin/plans");
  back("/admin/plans", { ok: "Plan added." });
}

export async function savePaymentSettings(form: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("payment_settings").update({
    upi_id: s(form, "upi_id"), payee_name: s(form, "payee_name"), enabled: s(form, "enabled") === "on",
    activation_mode: s(form, "activation_mode"), updated_at: new Date().toISOString(),
  }).eq("id", 1);
  if (error) back("/admin/plans", { err: error.message });
  back("/admin/plans", { ok: "Payment settings saved." });
}

// ---------------- admins
export async function addAdmin(form: FormData) {
  await rpc("/admin/admins", "admin_add_admin", { p_email: s(form, "email"), p_role: s(form, "role") }, "Admin saved.");
}

export async function removeAdmin(form: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.from("admins").delete().eq("user_id", s(form, "id"));
  if (error) back("/admin/admins", { err: error.message });
  back("/admin/admins", { ok: "Admin removed." });
}
