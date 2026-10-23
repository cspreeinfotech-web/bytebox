import { addPlan, savePlan, setFreeMode, setFreePlans } from "@/app/admin/actions";
import { ConfirmSubmit } from "@/components/confirm-submit";
import { ConfirmSelect, PlanForm, type PlanValues } from "@/components/settings-forms";
import { AdminShell } from "@/components/shell";
import { Badge, Card, Flash, PageHeader, btn } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { rupeesWhole } from "@/lib/format";

type Plan = Required<PlanValues> & { id: number };
const FREE_OPTIONS: [string, string][] = [
  ["none", "Off"], ["organic", "Free for organic users only"], ["ads", "Free for ads users only"], ["everyone", "Free for everyone"],
];

export default async function Plans({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const { supabase, user, counters } = await requireAdmin({ owner: true });
  const [{ data: plans }, { data: mode }, { data: subs }, { data: claims }] = await Promise.all([
    supabase.from("plans").select("*").order("position"),
    supabase.from("app_mode").select("free_mode, free_plans_for").eq("id", 1).single(),
    supabase.rpc("admin_plan_subscribers"),
    supabase.rpc("admin_free_claims"),
  ]);
  const count = new Map(((subs ?? []) as { plan_code: string; active: number; total_paid: number }[]).map((x) => [x.plan_code, x]));
  const free = Boolean(mode?.free_mode);
  const freeFor = (mode?.free_plans_for as string) ?? "none";
  const c = (claims ?? {}) as { organic?: number; ads?: number };
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Plans" subtitle="Every change reaches the app within seconds — no app update needed." />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || undefined} />

      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        <Card className={free ? "border-emerald-300 bg-emerald-50" : ""}>
          <form action={setFreeMode} className="flex h-full flex-col justify-between gap-4">
            <div>
              <div className="text-lg font-bold">Free mode {free ? <Badge color="green">ON</Badge> : <Badge>OFF</Badge>}</div>
              <p className="mt-1 text-sm text-gray-600">
                ON: no prices or payments anywhere in the app; logged-in users get 15 GB; ads users get full access;
                organic users can request full access.
              </p>
            </div>
            <input type="hidden" name="free_mode" value={free ? "off" : "on"} />
            <ConfirmSubmit message={free ? "Turn free mode OFF? Paid plans and prices come back in the app." : "Turn free mode ON? Prices and payments disappear from the app."}
              className={free ? btn.secondary : btn.primary}>{free ? "Turn OFF" : "Turn ON"}</ConfirmSubmit>
          </form>
        </Card>
        <Card className={freeFor !== "none" ? "border-sky-300 bg-sky-50" : ""}>
          <div className="text-lg font-bold">Free plans <Badge color={freeFor === "none" ? "gray" : "blue"}>{FREE_OPTIONS.find(([k]) => k === freeFor)?.[1]}</Badge></div>
          <ul className="mt-1 mb-3 space-y-0.5 text-sm text-gray-600">
            <li><b>Off</b> — everyone pays for plans.</li>
            <li><b>Organic only</b> — organic users see eligible plans as FREE (Activate for free); ads users still pay.</li>
            <li><b>Ads only</b> — ads users get eligible plans free; organic users still pay.</li>
            <li><b>Everyone</b> — all users get eligible plans free. Each user can claim each plan once per promotion.</li>
          </ul>
          <ConfirmSelect action={setFreePlans} name="free_plans_for" value={freeFor} options={FREE_OPTIONS}
            message="Users in this group will get plans without paying. Continue?" button="Apply" />
          <p className="mt-3 text-sm text-gray-600">Free plans claimed (this promotion): organic <b>{c.organic ?? 0}</b> · ads <b>{c.ads ?? 0}</b></p>
        </Card>
      </div>

      <h2 className="mb-3 text-lg font-bold">Plans</h2>
      <div className="mb-6 grid gap-4">
        {((plans ?? []) as Plan[]).map((p) => (
          <Card key={p.id}>
            <div className="mb-3 flex flex-wrap items-center gap-2">
              <span className="font-bold">{p.name} · {rupeesWhole(p.price_inr)} / {p.duration_days} days</span>
              {!p.active && <Badge color="red">hidden</Badge>}
              {p.free_eligible && freeFor !== "none" && <Badge color="blue">free now</Badge>}
              <span className="text-sm text-gray-500">{count.get(p.code)?.active ?? 0} active subscribers · {count.get(p.code)?.total_paid ?? 0} orders</span>
            </div>
            <PlanForm action={savePlan} plan={p} />
          </Card>
        ))}
        <Card>
          <h3 className="mb-3 font-semibold">Add plan</h3>
          <PlanForm action={addPlan} isNew />
        </Card>
      </div>
      <p className="text-sm text-gray-500">UPI ID, payee name and activation mode are on the <a className="text-accent underline" href="/admin/payments">Payments</a> page.</p>
    </AdminShell>
  );
}
