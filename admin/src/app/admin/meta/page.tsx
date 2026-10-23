import { configureMeta, sendMetaTest } from "@/app/admin/actions";
import { ApkUpload } from "@/components/apk-upload";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Flash, PageHeader, Stat, btn, input } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { SITE_URL } from "@/lib/env";
import { istDate } from "@/lib/format";

type MetaStatus = {
  pixel_id: string | null; token_set: boolean; token_hint: string | null; test_event_code: string | null;
  graph_version: string; enabled: boolean; counts_24h: Record<string, number>; by_event_7d: Record<string, number>;
  last_sent_at: string | null; last_error: string | null; clicks_24h: number; matched_installs_7d: number;
};

export default async function Meta({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const [{ data, error }, { data: site }] = await Promise.all([
    supabase.rpc("admin_meta_status"),
    supabase.from("site_settings").select("ads_apk_path, organic_apk_path").eq("id", 1).single(),
  ]);
  const m = (data ?? {}) as MetaStatus;
  const healthy = m.token_set && m.pixel_id && m.enabled && !(m.counts_24h?.failed > 0);
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Meta Pixel" subtitle="Pixel on the ads download page + Conversions API events (install, registration, purchase)." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || error?.message} />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="Health" value={healthy ? <Badge color="green">Working</Badge> : <Badge color="amber">Needs attention</Badge>} />
        <Stat label="Ad clicks (24 h)" value={m.clicks_24h ?? 0} />
        <Stat label="Installs matched to a click (7 d)" value={m.matched_installs_7d ?? 0} />
        <Stat label="Last event sent" value={<span className="text-base">{istDate(m.last_sent_at)}</span>} />
      </div>

      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <h2 className="mb-2 font-semibold">Events (last 24 h)</h2>
          <div className="flex flex-wrap gap-2">
            {Object.entries(m.counts_24h ?? {}).length === 0 ? <span className="text-sm text-gray-500">No events yet</span> :
              Object.entries(m.counts_24h).map(([k, v]) => <Badge key={k} color={k === "sent" ? "green" : k === "failed" ? "red" : "amber"}>{k}: {v}</Badge>)}
          </div>
          <h2 className="mb-2 mt-4 font-semibold">Sent by type (7 days)</h2>
          <div className="flex flex-wrap gap-2">
            {Object.entries(m.by_event_7d ?? {}).map(([k, v]) => <Badge key={k} color="violet">{k}: {v}</Badge>)}
          </div>
          {m.last_error && <p className="mt-4 break-all rounded-lg bg-red-50 p-3 text-xs text-red-700">Last error: {m.last_error}</p>}
          <form action={sendMetaTest} className="mt-4">
            <ConfirmSubmit message="Send a test Purchase event (₹49) with your Test Event Code?" className={btn.secondary}>Send test event</ConfirmSubmit>
            <p className="mt-2 text-xs text-gray-500">Check Events Manager → Test events within about a minute.</p>
          </form>
        </Card>
        <Card>
          <h2 className="mb-3 font-semibold">Settings</h2>
          <form action={configureMeta} className="grid gap-3">
            <label className="text-xs font-medium">Pixel / Dataset ID<input name="pixel_id" defaultValue={m.pixel_id ?? ""} inputMode="numeric" className={input} /></label>
            <label className="text-xs font-medium">Conversions API access token {m.token_set && <span className="text-gray-500">(saved {m.token_hint} — leave empty to keep)</span>}
              <input name="token" type="password" autoComplete="off" className={input} /></label>
            <label className="text-xs font-medium">Test Event Code<input name="test_event_code" defaultValue={m.test_event_code ?? ""} className={input} /></label>
            <label className="text-xs font-medium">Graph API version<input name="graph_version" defaultValue={m.graph_version ?? "v23.0"} className={input} /></label>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" name="enabled" defaultChecked={m.enabled ?? true} /> Send events</label>
            <button className={btn.primary}>Save</button>
          </form>
        </Card>
      </div>

      <Card>
        <h2 className="mb-1 font-semibold">APK downloads</h2>
        <p className="mb-4 text-sm text-gray-500">
          Download the APKs from the latest <b>mobile</b> workflow run (artifact <code>Bytebox-apks</code>), then upload here.
          Use <code>{SITE_URL}/d</code> as the website URL in your Meta ads.
        </p>
        <div className="grid gap-4 md:grid-cols-2">
          <ApkUpload kind="ads" current={site?.ads_apk_path ?? null} />
          <ApkUpload kind="organic" current={site?.organic_apk_path ?? null} />
        </div>
      </Card>
    </AdminShell>
  );
}
