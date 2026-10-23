import Link from "next/link";
import { clearUpi, markPaid, revokePayment, setUpi } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { UpiForm } from "@/components/settings-forms";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Empty, Flash, PageHeader, btn, input, statusColor } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { istDate, rupees } from "@/lib/format";

type Order = {
  id: string; reference: string; email: string | null; user_source: string; plan_name: string; amount_paise: number;
  price_inr_at_order: number | null; duration_days_at_order: number | null; upi_id_used: string | null; source: string;
  status: string; utr: string | null; reason: string | null; activated_by: string | null;
  created_at: string; paid_at: string | null; total: number;
};
type Upi = { upi_id: string | null; payee_name: string | null; enabled: boolean; activation_mode: string; live: boolean;
  updated_at: string | null; updated_by_email: string | null };
type Audit = { table_name: string; record: string | null; field: string; old_value: string | null; new_value: string | null;
  changed_by_email: string | null; changed_at: string };

const filters = [
  ["all", "All"], ["activated_today", "Activated today — verify against bank"], ["pending", "Needs review"],
  ["open", "Open"], ["success", "Paid"], ["revoked", "Reversed"],
] as const;
const sources: [string, string][] = [["", "Any source"], ["upi_app", "UPI"], ["admin", "Admin"], ["free_promo", "Free promo"], ["provider_api", "Provider"]];
const sourceBadge: Record<string, { label: string; color: "blue" | "violet" | "green" | "gray" }> = {
  upi_app: { label: "UPI", color: "blue" }, admin: { label: "Admin", color: "violet" },
  free_promo: { label: "Free promo", color: "green" }, provider_api: { label: "Provider", color: "gray" },
};
const fieldLabel = (t: string, f: string, r: string | null) =>
  t === "plans" ? `Plan ${r ?? ""} · ${f.replace(/_/g, " ")}` : t === "app_mode" ? f.replace(/_/g, " ") : `UPI · ${f.replace(/_/g, " ")}`;

export default async function Payments({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const filter = one(sp.filter) || "all";
  const q = one(sp.q);
  const src = one(sp.source);
  const ut = one(sp.user);
  const page = Math.max(1, Number(one(sp.page) || 1));
  const qs = new URLSearchParams({ filter, q, source: src, user: ut, page: String(page) }).toString();
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const [{ data, error }, { data: upiData }, { data: hist }] = await Promise.all([
    supabase.rpc("admin_payments", { p_filter: filter, p_search: q || null, p_limit: 50, p_offset: (page - 1) * 50,
      p_source: src || null, p_user_type: ut || null }),
    supabase.rpc("admin_payment_settings"),
    supabase.rpc("admin_settings_history", { p_limit: 40 }),
  ]);
  const rows = (data ?? []) as Order[];
  const total = rows[0]?.total ?? 0;
  const upi = (upiData ?? {}) as Upi;
  const link = (over: Record<string, string>) => `/admin/payments?${new URLSearchParams({ filter, q, source: src, user: ut, ...over }).toString()}`;

  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Payments" subtitle="UPI settings, change history and every order." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />

      <Card className="mb-6">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="text-lg font-bold">UPI settings {upi.live ? <Badge color="green">Payments live</Badge> : <Badge color="red">Payments off</Badge>}</div>
            <div className="mt-1 text-sm text-gray-600">
              {upi.upi_id ? <>Payments go to <b className="font-mono">{upi.upi_id}</b> · <b>{upi.payee_name}</b></> : <b className="text-red-600">No UPI ID — payments are paused in the app</b>}
              {" · "}{upi.activation_mode === "manual" ? "Manual activation" : "Instant activation"}{!upi.enabled && " · disabled"}
            </div>
            {upi.updated_at && <div className="text-xs text-gray-400">Last changed {istDate(upi.updated_at)}{upi.updated_by_email ? ` by ${upi.updated_by_email}` : ""}</div>}
          </div>
          {upi.upi_id && (
            <form action={clearUpi}>
              <ConfirmSubmit message="Payments will stop in the app until you add a UPI ID." className={btn.secondary}>Clear UPI ID</ConfirmSubmit>
            </form>
          )}
        </div>
        <UpiForm action={setUpi} current={{ upi_id: upi.upi_id, payee_name: upi.payee_name, enabled: upi.enabled ?? true, activation_mode: upi.activation_mode ?? "instant" }} />
        <p className="mt-3 text-xs text-gray-500">
          Instant: a plan starts as soon as the UPI app reports success and the order number, a unique transaction id, the 2-hour window and the
          3-per-day limit all check out. Manual: every payment waits in “Needs review” until you Mark paid with the UTR.
        </p>
      </Card>

      <Card className="mb-6 overflow-x-auto p-0">
        <div className="px-5 pt-4 font-semibold">Change history</div>
        {((hist ?? []) as Audit[]).length === 0 ? <Empty text="No changes yet." /> : (
          <table className="mt-2 w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500"><tr><th className="px-4 py-2">Field</th><th className="px-4 py-2">Old → New</th><th className="px-4 py-2">By</th><th className="px-4 py-2">When</th></tr></thead>
            <tbody className="divide-y divide-gray-100">
              {((hist ?? []) as Audit[]).map((a, i) => (
                <tr key={i}>
                  <td className="px-4 py-2 font-medium">{fieldLabel(a.table_name, a.field, a.record)}</td>
                  <td className="px-4 py-2 font-mono text-xs"><span className="text-gray-500">{a.old_value ?? "—"}</span> → <span>{a.new_value ?? "—"}</span></td>
                  <td className="px-4 py-2 text-gray-600">{a.changed_by_email ?? "system"}</td>
                  <td className="px-4 py-2 text-gray-500">{istDate(a.changed_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>

      <div className="mb-3 flex flex-wrap gap-2">
        {filters.map(([k, label]) => <Link key={k} href={link({ filter: k, page: "1" })} className={filter === k ? btn.primary : btn.secondary}>{label}</Link>)}
      </div>
      <form className="mb-4 flex flex-wrap gap-2">
        <input type="hidden" name="filter" value={filter} />
        <input name="q" defaultValue={q} placeholder="Order number, UTR or email" className={`${input} max-w-xs`} />
        <select name="source" defaultValue={src} className={`${input} w-auto`}>{sources.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        <select name="user" defaultValue={ut} className={`${input} w-auto`}>
          <option value="">Any user</option><option value="ads">Ads users</option><option value="organic">Organic users</option>
        </select>
        <button className={btn.secondary}>Apply</button>
      </form>
      <Card className="overflow-x-auto p-0">
        {rows.length === 0 ? <Empty /> : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500">
              <tr><th className="px-4 py-3">Order</th><th className="px-4 py-3">User</th><th className="px-4 py-3">Plan at order</th><th className="px-4 py-3">UPI ID used</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Action</th></tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map((o) => (
                <tr key={o.id} className="align-top">
                  <td className="px-4 py-3"><div className="font-mono font-semibold">{o.reference}</div>
                    <div className="text-xs text-gray-500">{istDate(o.created_at)}</div>
                    <div className="mt-1"><Badge color={sourceBadge[o.source]?.color ?? "gray"}>{sourceBadge[o.source]?.label ?? o.source}</Badge></div>
                    {o.utr && <div className="font-mono text-xs text-gray-600">UTR {o.utr}</div>}</td>
                  <td className="px-4 py-3">{o.email ?? <span className="text-gray-400">deleted account</span>}
                    <div><Badge color={o.user_source === "ads" ? "violet" : "blue"}>{o.user_source}</Badge></div></td>
                  <td className="px-4 py-3">{o.plan_name}<div className="font-semibold">{o.source === "free_promo" ? <>₹0 <span className="text-xs font-normal text-gray-500 line-through">₹{o.price_inr_at_order}</span></> : rupees(o.amount_paise)}</div>
                    <div className="text-xs text-gray-500">{o.duration_days_at_order ?? "—"} days</div></td>
                  <td className="px-4 py-3 font-mono text-xs">{o.upi_id_used ?? "—"}</td>
                  <td className="px-4 py-3">
                    <Badge color={statusColor(o.status)}>{o.status === "revoked" ? "reversed" : o.status}</Badge>
                    {o.paid_at && <div className="mt-1 text-xs text-gray-500">{istDate(o.paid_at)}</div>}
                    {o.reason && <div className="mt-1 max-w-xs text-xs text-gray-500">{o.reason}</div>}
                  </td>
                  <td className="px-4 py-3">
                    {o.source === "free_promo" ? null : o.status === "success" ? (
                      <form action={revokePayment} className="flex flex-col gap-2">
                        <input type="hidden" name="id" value={o.id} /><input type="hidden" name="qs" value={qs} />
                        <input name="reason" required minLength={3} placeholder="Reason (not in bank, refunded…)" className={input} />
                        <ConfirmSubmit message="Revoke this payment? The plan ends now and the transaction id is blocked." className={btn.small}>Revoke</ConfirmSubmit>
                      </form>
                    ) : o.status !== "revoked" ? (
                      <form action={markPaid} className="flex flex-col gap-2">
                        <input type="hidden" name="id" value={o.id} /><input type="hidden" name="qs" value={qs} />
                        <input name="utr" required defaultValue={o.utr ?? ""} placeholder="UTR / transaction id" className={`${input} font-mono`} />
                        <ConfirmSubmit message="Mark as paid and activate the plan?" className={btn.small}>Mark paid</ConfirmSubmit>
                      </form>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
      {total > 50 && (
        <div className="mt-4 flex gap-2 text-sm">
          {page > 1 && <Link className={btn.secondary} href={link({ page: String(page - 1) })}>Previous</Link>}
          {page * 50 < total && <Link className={btn.secondary} href={link({ page: String(page + 1) })}>Next</Link>}
        </div>
      )}
    </AdminShell>
  );
}
