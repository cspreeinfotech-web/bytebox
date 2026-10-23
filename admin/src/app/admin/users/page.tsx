import Link from "next/link";
import { setAccess } from "@/app/admin/actions";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Empty, Flash, PageHeader, btn, input, statusColor } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { istDate } from "@/lib/format";

type U = {
  id: string; email: string | null; display_name: string; source: string; ads_access_status: string; is_guest: boolean;
  plan_name: string | null; plan_ends_at: string | null; admin_role: string | null; created_at: string; total: number;
};
const filters = [["all", "All"], ["members", "Accounts"], ["guests", "Guests"], ["ads", "Ads"], ["organic", "Organic"], ["premium", "Premium"]] as const;

export default async function Users({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const filter = one(sp.filter) || "members";
  const q = one(sp.q);
  const page = Math.max(1, Number(one(sp.page) || 1));
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const { data, error } = await supabase.rpc("admin_users", { p_search: q || null, p_filter: filter, p_limit: 50, p_offset: (page - 1) * 50 });
  const rows = (data ?? []) as U[];
  const total = rows[0]?.total ?? 0;
  const here = `/admin/users?filter=${filter}&q=${encodeURIComponent(q)}&page=${page}`;
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Users" subtitle={`${total.toLocaleString("en-IN")} matching`} />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />
      <div className="mb-4 flex flex-wrap gap-2">
        {filters.map(([k, l]) => <Link key={k} href={`/admin/users?filter=${k}`} className={filter === k ? btn.primary : btn.secondary}>{l}</Link>)}
      </div>
      <form className="mb-4 flex gap-2"><input type="hidden" name="filter" value={filter} />
        <input name="q" defaultValue={q} placeholder="Email, name or user id" className={`${input} max-w-sm`} /><button className={btn.secondary}>Search</button></form>
      <Card className="overflow-x-auto p-0">
        {rows.length === 0 ? <Empty /> : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500"><tr><th className="px-4 py-3">User</th><th className="px-4 py-3">Source</th><th className="px-4 py-3">Plan</th><th className="px-4 py-3">Ads access</th></tr></thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map((u) => (
                <tr key={u.id}>
                  <td className="px-4 py-3"><div className="font-semibold">{u.display_name} {u.admin_role && <Badge color="violet">{u.admin_role}</Badge>}</div>
                    <div className="text-xs text-gray-500">{u.is_guest ? "Guest" : u.email} · {istDate(u.created_at)}</div>
                    <div className="font-mono text-[10px] text-gray-400">{u.id}</div></td>
                  <td className="px-4 py-3"><Badge color={u.source === "ads" ? "violet" : "blue"}>{u.source}</Badge></td>
                  <td className="px-4 py-3">{u.plan_name ? <><Badge color="green">{u.plan_name}</Badge><div className="text-xs text-gray-500">until {istDate(u.plan_ends_at)}</div></> : "—"}</td>
                  <td className="px-4 py-3">
                    {u.source === "ads" ? <Badge color="green">via ads</Badge> : (
                      <form action={setAccess} className="flex items-center gap-2">
                        <input type="hidden" name="id" value={u.id} /><input type="hidden" name="back" value={here} />
                        <Badge color={statusColor(u.ads_access_status)}>{u.ads_access_status}</Badge>
                        <select name="status" defaultValue={u.ads_access_status} className={`${input} w-auto`}>
                          <option value="none">none</option><option value="pending">pending</option><option value="approved">approved</option><option value="rejected">rejected</option>
                        </select>
                        <button className={btn.small}>Save</button>
                      </form>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
      {total > 50 && (
        <div className="mt-4 flex gap-2">
          {page > 1 && <Link className={btn.secondary} href={`/admin/users?filter=${filter}&q=${q}&page=${page - 1}`}>Previous</Link>}
          {page * 50 < total && <Link className={btn.secondary} href={`/admin/users?filter=${filter}&q=${q}&page=${page + 1}`}>Next</Link>}
        </div>
      )}
    </AdminShell>
  );
}
