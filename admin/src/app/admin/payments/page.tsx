import Link from "next/link";
import { markPaid, revokePayment } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Empty, Flash, PageHeader, btn, input, statusColor } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { istDate, rupees } from "@/lib/format";

type Order = {
  id: string; reference: string; email: string | null; plan_name: string; amount_paise: number; status: string;
  utr: string | null; client_status: string | null; reason: string | null; activated_by: string | null;
  created_at: string; paid_at: string | null; total: number;
};

const filters = [
  ["all", "All"], ["activated_today", "Activated today — verify against bank"], ["pending", "Needs review"],
  ["open", "Open"], ["success", "Paid"], ["revoked", "Reversed"],
] as const;

export default async function Payments({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const filter = one(sp.filter) || "all";
  const q = one(sp.q);
  const page = Math.max(1, Number(one(sp.page) || 1));
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const { data, error } = await supabase.rpc("admin_payments", { p_filter: filter, p_search: q || null, p_limit: 50, p_offset: (page - 1) * 50 });
  const rows = (data ?? []) as Order[];
  const total = rows[0]?.total ?? 0;
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Payments" subtitle="UPI orders. Check activations against your bank statement; revoke anything you did not receive." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />
      <div className="mb-4 flex flex-wrap gap-2">
        {filters.map(([k, label]) => (
          <Link key={k} href={`/admin/payments?filter=${k}`} className={filter === k ? btn.primary : btn.secondary}>{label}</Link>
        ))}
      </div>
      <form className="mb-4 flex gap-2">
        <input type="hidden" name="filter" value={filter} />
        <input name="q" defaultValue={q} placeholder="Order number, UTR or email" className={`${input} max-w-sm`} />
        <button className={btn.secondary}>Search</button>
      </form>
      <Card className="overflow-x-auto p-0">
        {rows.length === 0 ? <Empty /> : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500">
              <tr><th className="px-4 py-3">Order</th><th className="px-4 py-3">User</th><th className="px-4 py-3">Plan · Amount</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Action</th></tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map((o) => (
                <tr key={o.id} className="align-top">
                  <td className="px-4 py-3"><div className="font-mono font-semibold">{o.reference}</div>
                    <div className="text-xs text-gray-500">{istDate(o.created_at)}</div>
                    {o.utr && <div className="font-mono text-xs text-gray-600">UTR {o.utr}</div>}</td>
                  <td className="px-4 py-3">{o.email ?? <span className="text-gray-400">deleted account</span>}</td>
                  <td className="px-4 py-3">{o.plan_name}<div className="font-semibold">{rupees(o.amount_paise)}</div></td>
                  <td className="px-4 py-3">
                    <Badge color={statusColor(o.status)}>{o.status === "revoked" ? "reversed" : o.status}</Badge>
                    {o.activated_by && <div className="mt-1 text-xs text-gray-500">by {o.activated_by} · {istDate(o.paid_at)}</div>}
                    {o.reason && <div className="mt-1 max-w-xs text-xs text-gray-500">{o.reason}</div>}
                  </td>
                  <td className="px-4 py-3">
                    {o.status === "success" ? (
                      <form action={revokePayment} className="flex flex-col gap-2">
                        <input type="hidden" name="id" value={o.id} /><input type="hidden" name="filter" value={filter} />
                        <input name="reason" required minLength={3} placeholder="Reason (not in bank, refunded…)" className={input} />
                        <ConfirmSubmit message="Revoke this payment? The plan ends now and the transaction id is blocked." className={btn.small}>Revoke</ConfirmSubmit>
                      </form>
                    ) : o.status !== "revoked" ? (
                      <form action={markPaid} className="flex flex-col gap-2">
                        <input type="hidden" name="id" value={o.id} /><input type="hidden" name="filter" value={filter} />
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
          {page > 1 && <Link className={btn.secondary} href={`/admin/payments?filter=${filter}&q=${q}&page=${page - 1}`}>Previous</Link>}
          {page * 50 < total && <Link className={btn.secondary} href={`/admin/payments?filter=${filter}&q=${q}&page=${page + 1}`}>Next</Link>}
        </div>
      )}
    </AdminShell>
  );
}
