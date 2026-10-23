import { addPlan, savePaymentSettings, savePlan, toggleFreeMode } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Flash, PageHeader, btn, input } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { rupeesWhole } from "@/lib/format";

type Plan = { id: number; code: string; name: string; price_inr: number; duration_days: number; perks: string[]; active: boolean; position: number; badge: string | null };

function PlanFields({ p }: { p?: Plan }) {
  return (
    <>
      <label className="text-xs font-medium">Name<input name="name" required defaultValue={p?.name} className={input} /></label>
      <label className="text-xs font-medium">Price (₹)<input name="price_inr" type="number" min={1} required defaultValue={p?.price_inr} className={input} /></label>
      <label className="text-xs font-medium">Days<input name="duration_days" type="number" min={1} required defaultValue={p?.duration_days} className={input} /></label>
      <label className="text-xs font-medium">Badge<input name="badge" defaultValue={p?.badge ?? ""} placeholder="Best value" className={input} /></label>
      <label className="text-xs font-medium">Position<input name="position" type="number" defaultValue={p?.position ?? 0} className={input} /></label>
      <label className="flex items-center gap-2 pt-5 text-sm"><input type="checkbox" name="active" defaultChecked={p?.active ?? true} /> Active</label>
      <label className="text-xs font-medium sm:col-span-6">Perks (one per line)
        <textarea name="perks" rows={3} defaultValue={(p?.perks ?? ["Full premium videos", "2 TB cloud storage", "Downloads"]).join("\n")} className={input} /></label>
    </>
  );
}

export default async function Plans({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const [{ data: plans }, { data: mode }, { data: subs }, { data: pay }] = await Promise.all([
    supabase.from("plans").select("*").order("position"),
    supabase.from("app_mode").select("free_mode").eq("id", 1).single(),
    supabase.rpc("admin_plan_subscribers"),
    supabase.from("payment_settings").select("*").eq("id", 1).single(),
  ]);
  const count = new Map(((subs ?? []) as { plan_code: string; active: number; total_paid: number }[]).map((s) => [s.plan_code, s]));
  const free = Boolean(mode?.free_mode);
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Plans" subtitle="Changes reach the app instantly (no update needed)." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || undefined} />

      <Card className={`mb-6 ${free ? "border-emerald-300 bg-emerald-50" : ""}`}>
        <form action={toggleFreeMode} className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <div className="text-lg font-bold">Free mode {free ? <Badge color="green">ON</Badge> : <Badge>OFF</Badge>}</div>
            <p className="max-w-2xl text-sm text-gray-600">
              When ON the app shows no plans, prices or UPI. Logged-in users get 15 GB cloud; organic users can request full access.
              Turning it OFF restores the paid flow immediately.
            </p>
          </div>
          <input type="hidden" name="free_mode" value={free ? "off" : "on"} />
          <ConfirmSubmit message={free ? "Turn free mode OFF and show paid plans again?" : "Turn free mode ON? Plans and prices disappear from the app."}
            className={free ? btn.secondary : btn.primary}>{free ? "Turn OFF" : "Turn ON"}</ConfirmSubmit>
        </form>
      </Card>

      <h2 className="mb-3 text-lg font-bold">Plans</h2>
      <div className="mb-6 grid gap-4">
        {((plans ?? []) as Plan[]).map((p) => (
          <Card key={p.id}>
            <div className="mb-3 flex flex-wrap items-center gap-3">
              <span className="font-mono text-xs text-gray-500">{p.code}</span>
              <span className="font-bold">{p.name} · {rupeesWhole(p.price_inr)} / {p.duration_days} days</span>
              {!p.active && <Badge color="red">inactive</Badge>}
              <Badge color="green">{count.get(p.code)?.active ?? 0} active subscribers</Badge>
              <Badge>{count.get(p.code)?.total_paid ?? 0} paid orders</Badge>
            </div>
            <form action={savePlan} className="grid gap-3 sm:grid-cols-6">
              <input type="hidden" name="id" value={p.id} />
              <PlanFields p={p} />
              <div className="sm:col-span-6"><button className={btn.primary}>Save plan</button></div>
            </form>
          </Card>
        ))}
        <Card>
          <h3 className="mb-3 font-semibold">Add plan</h3>
          <form action={addPlan} className="grid gap-3 sm:grid-cols-6">
            <label className="text-xs font-medium">Code<input name="code" required pattern="[a-z0-9_-]{2,30}" placeholder="festival" className={input} /></label>
            <PlanFields />
            <div className="sm:col-span-6"><button className={btn.primary}>Add plan</button></div>
          </form>
        </Card>
      </div>

      <h2 className="mb-3 text-lg font-bold">UPI payment settings</h2>
      <Card>
        <form action={savePaymentSettings} className="grid gap-3 sm:grid-cols-4">
          <label className="text-xs font-medium">UPI ID<input name="upi_id" required defaultValue={pay?.upi_id ?? ""} className={input} /></label>
          <label className="text-xs font-medium">Payee name (as your bank shows it)<input name="payee_name" required defaultValue={pay?.payee_name ?? ""} className={input} /></label>
          <label className="text-xs font-medium">Activation
            <select name="activation_mode" defaultValue={pay?.activation_mode ?? "instant"} className={input}>
              <option value="instant">Instant (with safeguards)</option><option value="manual">Manual (you mark paid)</option>
            </select></label>
          <label className="flex items-center gap-2 pt-5 text-sm"><input type="checkbox" name="enabled" defaultChecked={pay?.enabled ?? true} /> Payments enabled</label>
          <div className="sm:col-span-4"><button className={btn.primary}>Save settings</button></div>
        </form>
      </Card>
    </AdminShell>
  );
}
