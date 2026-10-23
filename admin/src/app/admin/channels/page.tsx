import { createChannel, deleteChannel, updateChannel } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Empty, Flash, PageHeader, btn, input, statusColor } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { istDate } from "@/lib/format";

type Channel = {
  id: string; name: string; category: string; review_status: string; publish_state: string; audience: string;
  created_via: string; member_count: number; created_at: string;
};

export default async function Channels({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const { supabase, user, counters } = await requireAdmin();
  const q = one(sp.q);
  let query = supabase.from("channels").select("id,name,category,review_status,publish_state,audience,created_via,member_count,created_at")
    .order("created_at", { ascending: false }).limit(200);
  if (q) query = query.ilike("name", `%${q}%`);
  const [{ data, error }, { data: cats }] = await Promise.all([
    query, supabase.from("categories").select("slug,name").order("position"),
  ]);
  const rows = (data ?? []) as Channel[];
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Channels" subtitle="Channels created here are approved immediately." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />
      <Card className="mb-6">
        <h2 className="mb-3 font-semibold">New channel</h2>
        <form action={createChannel} className="grid gap-3 md:grid-cols-6">
          <input name="name" required minLength={3} placeholder="Name" className={`${input} md:col-span-2`} />
          <select name="category" required className={input}>
            {(cats ?? []).map((c) => <option key={c.slug} value={c.slug}>{c.name}</option>)}
          </select>
          <select name="audience" className={input} defaultValue="all">
            <option value="all">Everyone</option><option value="organic">Organic only</option><option value="ads">Ads only</option>
          </select>
          <input name="tags" placeholder="tags, comma separated" className={`${input} md:col-span-2`} />
          <textarea name="description" placeholder="Description" className={`${input} md:col-span-5`} rows={2} />
          <button className={btn.primary}>Create</button>
        </form>
      </Card>
      <form className="mb-4 flex gap-2"><input name="q" defaultValue={q} placeholder="Search channels" className={`${input} max-w-sm`} /><button className={btn.secondary}>Search</button></form>
      <Card className="overflow-x-auto p-0">
        {rows.length === 0 ? <Empty /> : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500">
              <tr><th className="px-4 py-3">Channel</th><th className="px-4 py-3">Review</th><th className="px-4 py-3">Members</th><th className="px-4 py-3">Audience · State</th><th className="px-4 py-3" /></tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map((c) => (
                <tr key={c.id}>
                  <td className="px-4 py-3"><div className="font-semibold">{c.name}</div><div className="text-xs text-gray-500">{c.category} · {c.created_via} · {istDate(c.created_at)}</div></td>
                  <td className="px-4 py-3"><Badge color={statusColor(c.review_status)}>{c.review_status}</Badge></td>
                  <td className="px-4 py-3">{c.member_count}</td>
                  <td className="px-4 py-3">
                    <form action={updateChannel} className="flex flex-wrap gap-2">
                      <input type="hidden" name="id" value={c.id} />
                      <select name="audience" defaultValue={c.audience} className={`${input} w-auto`}>
                        <option value="all">Everyone</option><option value="organic">Organic</option><option value="ads">Ads</option>
                      </select>
                      <select name="publish_state" defaultValue={c.publish_state} className={`${input} w-auto`}>
                        <option value="active">Active</option><option value="disabled">Disabled</option><option value="draft">Draft</option>
                      </select>
                      <button className={btn.small}>Save</button>
                    </form>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <form action={deleteChannel}>
                      <input type="hidden" name="id" value={c.id} />
                      <ConfirmSubmit message={`Delete "${c.name}" and all its posts? This cannot be undone.`} className={btn.small}>Delete</ConfirmSubmit>
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
