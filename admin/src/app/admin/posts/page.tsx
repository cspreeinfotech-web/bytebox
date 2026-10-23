import Link from "next/link";
import { deletePost, handleReport, updatePost } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Empty, Flash, PageHeader, btn, input, statusColor } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { bytes, istDate } from "@/lib/format";

type Post = {
  id: string; title: string; status: string; audience: string; is_premium: boolean; kind: string; view_count: number;
  size_bytes: number | null; published_at: string | null; created_at: string; channel: { name: string } | null;
};
type Report = {
  id: number; reason: string; details: string | null; contact: string | null; source: string; status: string; created_at: string;
  post_id: string | null; post: { title: string } | null; channel: { name: string } | null;
};

const reasonLabel: Record<string, string> = {
  sexual: "Sexual or nude content", violence: "Violence or dangerous content", hate: "Hate speech or harassment",
  copyright: "Copyright", spam: "Spam, scam or misleading", other: "Other",
};

export default async function Posts({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const tab = one(sp.tab) || "posts";
  const { supabase, user, counters } = await requireAdmin();
  const tabs = (
    <div className="mb-5 flex gap-2">
      <Link href="/admin/posts" className={tab === "posts" ? btn.primary : btn.secondary}>Posts</Link>
      <Link href="/admin/posts?tab=reports" className={tab === "reports" ? btn.primary : btn.secondary}>
        Reports {counters.reports ? `(${counters.reports})` : ""}
      </Link>
    </div>
  );

  if (tab === "reports") {
    const { data, error } = await supabase.from("reports")
      .select("id,reason,details,contact,source,status,created_at,post_id,post:posts(title),channel:channels(name)")
      .order("status", { ascending: false }).order("created_at", { ascending: false }).limit(200);
    const rows = (data ?? []) as unknown as Report[];
    return (
      <AdminShell counters={counters} email={user.email}>
        <PageHeader title="Posts" subtitle="Reports from the app and the website" />
        {tabs}
        <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />
        <Card className="overflow-x-auto p-0">
          {rows.length === 0 ? <Empty /> : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500"><tr><th className="px-4 py-3">Report</th><th className="px-4 py-3">Content</th><th className="px-4 py-3">Status</th><th className="px-4 py-3" /></tr></thead>
              <tbody className="divide-y divide-gray-100">
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td className="px-4 py-3"><div className="font-semibold">{reasonLabel[r.reason] ?? r.reason}</div>
                      <div className="text-xs text-gray-500">{r.source} · {istDate(r.created_at)}</div>
                      {r.details && <div className="mt-1 max-w-md text-gray-700">{r.details}</div>}
                      {r.contact && <div className="text-xs text-gray-500">Contact: {r.contact}</div>}</td>
                    <td className="px-4 py-3">{r.post?.title ?? "—"}<div className="text-xs text-gray-500">{r.channel?.name}</div></td>
                    <td className="px-4 py-3"><Badge color={statusColor(r.status)}>{r.status}</Badge></td>
                    <td className="px-4 py-3">
                      {r.status === "open" && (
                        <form action={handleReport} className="flex gap-2">
                          <input type="hidden" name="id" value={r.id} />
                          <button name="status" value="actioned" className={btn.small}>Actioned</button>
                          <button name="status" value="dismissed" className={btn.small}>Dismiss</button>
                        </form>
                      )}
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

  const q = one(sp.q);
  let query = supabase.from("posts")
    .select("id,title,status,audience,is_premium,kind,view_count,size_bytes,published_at,created_at,channel:channels(name)")
    .order("created_at", { ascending: false }).limit(200);
  if (q) query = query.ilike("title", `%${q}%`);
  const { data, error } = await query;
  const rows = (data ?? []) as unknown as Post[];
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Posts" />
      {tabs}
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />
      <form className="mb-4 flex gap-2"><input name="q" defaultValue={q} placeholder="Search titles" className={`${input} max-w-sm`} /><button className={btn.secondary}>Search</button></form>
      <Card className="overflow-x-auto p-0">
        {rows.length === 0 ? <Empty /> : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500"><tr><th className="px-4 py-3">Post</th><th className="px-4 py-3">Views</th><th className="px-4 py-3">Status · Audience · Premium</th><th className="px-4 py-3" /></tr></thead>
            <tbody className="divide-y divide-gray-100">
              {rows.map((p) => (
                <tr key={p.id}>
                  <td className="px-4 py-3"><div className="font-semibold">{p.title}</div>
                    <div className="text-xs text-gray-500">{p.channel?.name} · {p.kind} · {p.size_bytes ? bytes(p.size_bytes) : "—"} · {istDate(p.published_at ?? p.created_at)}</div></td>
                  <td className="px-4 py-3">{p.view_count}</td>
                  <td className="px-4 py-3">
                    <form action={updatePost} className="flex flex-wrap items-center gap-2">
                      <input type="hidden" name="id" value={p.id} />
                      <select name="status" defaultValue={p.status} className={`${input} w-auto`}>
                        <option value="published">Published</option><option value="draft">Draft</option><option value="removed">Removed</option>
                      </select>
                      <select name="audience" defaultValue={p.audience} className={`${input} w-auto`}>
                        <option value="all">Everyone</option><option value="organic">Organic</option><option value="ads">Ads</option>
                      </select>
                      <label className="flex items-center gap-1 text-xs"><input type="checkbox" name="is_premium" defaultChecked={p.is_premium} /> Premium</label>
                      <button className={btn.small}>Save</button>
                    </form>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <form action={deletePost}><input type="hidden" name="id" value={p.id} />
                      <ConfirmSubmit message="Delete this post and its files?" className={btn.small}>Delete</ConfirmSubmit></form>
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
