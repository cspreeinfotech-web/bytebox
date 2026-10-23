import { reviewChannel } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Empty, Flash, PageHeader, btn, input } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { istDate } from "@/lib/format";

type Pending = {
  id: string; name: string; description: string; category: string; tags: string[]; icon_key: string | null;
  created_at: string; owner_name: string | null; owner_email: string | null; owner_source: string;
};

export default async function Approvals({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const { data, error } = await supabase.rpc("admin_pending_channels");
  const rows = (data ?? []) as Pending[];
  const icons = new Map<string, string>();
  for (const r of rows) {
    if (!r.icon_key) continue;
    const { data: s } = await supabase.storage.from("media").createSignedUrl(r.icon_key, 3600);
    if (s?.signedUrl) icons.set(r.id, s.signedUrl);
  }
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Approvals" subtitle="Channels created in the app wait here until you approve them." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />
      {rows.length === 0 ? (
        <Card><Empty text="No channels waiting for approval." /></Card>
      ) : (
        <div className="grid gap-4 xl:grid-cols-2">
          {rows.map((c) => (
            <Card key={c.id}>
              <div className="flex gap-4">
                {icons.get(c.id) ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={icons.get(c.id)} alt="" className="h-16 w-16 rounded-full object-cover" />
                ) : (
                  <div className="grid h-16 w-16 place-items-center rounded-full bg-gradient-to-br from-accent to-accent-2 text-xl font-bold text-white">
                    {c.name[0]?.toUpperCase()}
                  </div>
                )}
                <div className="min-w-0 flex-1">
                  <div className="text-lg font-bold">{c.name}</div>
                  <div className="text-sm text-gray-500">
                    by {c.owner_name ?? "—"} ({c.owner_email ?? "no email"}) ·{" "}
                    <Badge color={c.owner_source === "ads" ? "violet" : "blue"}>{c.owner_source} user</Badge> · {istDate(c.created_at)}
                  </div>
                  <div className="mt-2 text-sm"><Badge>{c.category}</Badge> {c.tags.map((t) => <span key={t} className="ml-1 text-xs text-gray-500">#{t}</span>)}</div>
                  {c.description && <p className="mt-2 text-sm text-gray-700">{c.description}</p>}
                </div>
              </div>
              <form action={reviewChannel} className="mt-4 flex flex-wrap items-end gap-3">
                <input type="hidden" name="id" value={c.id} />
                <label className="text-sm">
                  <span className="mb-1 block font-medium">Audience</span>
                  <select name="audience" defaultValue="all" className={input}>
                    <option value="all">Everyone</option>
                    <option value="organic">Organic users only</option>
                    <option value="ads">Ads users only</option>
                  </select>
                </label>
                <input name="reason" placeholder="Reason (if rejecting)" className={`${input} max-w-xs flex-1`} />
                <button name="decision" value="approve" className={btn.success}>Approve</button>
                <ConfirmSubmit name="decision" value="reject" message="Reject this channel?" className={btn.danger}>
                  Reject
                </ConfirmSubmit>
              </form>
            </Card>
          ))}
        </div>
      )}
    </AdminShell>
  );
}
