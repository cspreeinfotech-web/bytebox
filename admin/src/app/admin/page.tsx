import Link from "next/link";
import { AdminShell } from "@/components/shell";
import { Flash, PageHeader, Stat } from "@/components/ui";
import { one, requireAdmin, type SP } from "@/lib/admin";
import { rupees } from "@/lib/format";

type Dash = Record<string, number | boolean>;

export default async function Dashboard({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  const { supabase, user, counters } = await requireAdmin();
  const { data } = await supabase.rpc("admin_dashboard");
  const d = (data ?? {}) as Dash;
  const owner = counters.role === "owner";
  const n = (k: string) => Number(d[k] ?? 0).toLocaleString("en-IN");
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Dashboard" subtitle={d.free_mode ? "Free mode is ON" : "Paid mode"} />
      <Flash ok={one(sp.ok) || undefined} err={one(sp.err) || undefined} />
      {Number(d.pending_channels) > 0 && owner && (
        <Link href="/admin/approvals" className="mb-6 flex items-center justify-between rounded-2xl border border-amber-300 bg-amber-50 px-5 py-4 font-semibold text-amber-800">
          <span>{n("pending_channels")} channel{Number(d.pending_channels) === 1 ? "" : "s"} waiting for approval</span>
          <span>Review →</span>
        </Link>
      )}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {owner && (
          <>
            <Stat label="Activated today — verify against bank" value={n("activated_today")} href="/admin/payments?filter=activated_today" tone={Number(d.activated_today) > 0 ? "amber" : undefined} />
            <Stat label="Revenue today" value={rupees(Number(d.revenue_today_paise))} />
            <Stat label="Revenue (30 days)" value={rupees(Number(d.revenue_30d_paise))} />
            <Stat label="Active Premium" value={n("active_premium")} />
            <Stat label="Payments to verify" value={n("pending_payments")} href="/admin/payments?filter=pending" />
            <Stat label="Access requests" value={n("pending_requests")} href="/admin/requests" />
            <Stat label="Accounts (logged in)" value={n("users")} href="/admin/users" />
            <Stat label="Guests" value={n("guests")} />
            <Stat label="Ads users" value={n("ads_users")} />
            <Stat label="Organic users" value={n("organic_users")} />
            <Stat label="Installs today" value={n("installs_today")} />
          </>
        )}
        <Stat label="Live channels" value={n("channels")} href="/admin/channels" />
        <Stat label="Published posts" value={n("posts")} href="/admin/posts" />
        <Stat label="Open reports" value={n("open_reports")} href="/admin/posts?tab=reports" tone={Number(d.open_reports) > 0 ? "amber" : undefined} />
      </div>
    </AdminShell>
  );
}
