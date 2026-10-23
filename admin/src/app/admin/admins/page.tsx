import { addAdmin, removeAdmin } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Flash, PageHeader, btn, input } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { istDate } from "@/lib/format";

type A = { user_id: string; email: string; display_name: string; role: string; created_at: string };

export default async function Admins({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const { data, error } = await supabase.rpc("admin_list_admins");
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Admins" subtitle="Owners see everything. Content admins manage channels and posts only." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />
      <Card className="mb-6">
        <form action={addAdmin} className="flex flex-wrap items-end gap-3">
          <label className="text-xs font-medium">Email of an existing account<input name="email" type="email" required className={`${input} w-72`} /></label>
          <label className="text-xs font-medium">Role<select name="role" className={input}><option value="content">Content admin</option><option value="owner">Owner</option></select></label>
          <button className={btn.primary}>Add / change role</button>
        </form>
      </Card>
      <Card className="p-0">
        <table className="w-full text-sm">
          <tbody className="divide-y divide-gray-100">
            {((data ?? []) as A[]).map((a) => (
              <tr key={a.user_id}>
                <td className="px-4 py-3"><div className="font-semibold">{a.display_name}</div><div className="text-xs text-gray-500">{a.email}</div></td>
                <td className="px-4 py-3"><Badge color={a.role === "owner" ? "violet" : "blue"}>{a.role}</Badge></td>
                <td className="px-4 py-3 text-gray-500">{istDate(a.created_at)}</td>
                <td className="px-4 py-3 text-right">
                  <form action={removeAdmin}><input type="hidden" name="id" value={a.user_id} />
                    <ConfirmSubmit message={`Remove ${a.email} as admin?`} className={btn.small}>Remove</ConfirmSubmit></form>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </AdminShell>
  );
}
