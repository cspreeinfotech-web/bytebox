import { setAccess } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Empty, Flash, PageHeader, btn } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { istDate } from "@/lib/format";

type R = { id: string; email: string; display_name: string; source: string; requested_at: string | null; plan_name: string | null; paid: boolean };

export default async function Requests({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const { data, error } = await supabase.rpc("admin_access_requests");
  const rows = (data ?? []) as R[];
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Requests" subtitle="Organic users asking for full access (ads content). Paying organic users appear here automatically." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />
      <Card className="overflow-x-auto p-0">
        {rows.length === 0 ? <Empty text="No pending requests." /> : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500"><tr><th className="px-4 py-3">User</th><th className="px-4 py-3">Requested</th><th className="px-4 py-3">Plan</th><th className="px-4 py-3" /></tr></thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map((r) => (
                <tr key={r.id}>
                  <td className="px-4 py-3"><div className="font-semibold">{r.display_name}</div><div className="text-xs text-gray-500">{r.email}</div></td>
                  <td className="px-4 py-3">{istDate(r.requested_at)}</td>
                  <td className="px-4 py-3">{r.plan_name ? <Badge color="green">{r.plan_name}</Badge> : r.paid ? <Badge>paid before</Badge> : "—"}</td>
                  <td className="px-4 py-3">
                    <form action={setAccess} className="flex justify-end gap-2">
                      <input type="hidden" name="id" value={r.id} /><input type="hidden" name="back" value="/admin/requests" />
                      <button name="status" value="approved" className={btn.success}>Approve</button>
                      <ConfirmSubmit name="status" value="rejected" message="Reject this request?" className={btn.secondary}>Reject</ConfirmSubmit>
                    </form>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </AdminShell>
  );
}
