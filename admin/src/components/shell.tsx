import type { ReactNode } from "react";
import { NavLink } from "@/components/nav-link";
import type { Counters } from "@/lib/admin";
import { signOut } from "@/app/admin/actions";

/** Sidebar + content frame for every admin page. */
export function AdminShell({ counters, email, children }: { counters: Counters; email?: string; children: ReactNode }) {
  const owner = counters.role === "owner";
  return (
    <div className="lg:flex">
      <aside className="border-b border-gray-200 bg-white lg:sticky lg:top-0 lg:h-screen lg:w-64 lg:shrink-0 lg:border-b-0 lg:border-r">
        <div className="flex items-center gap-3 px-5 py-5">
          <div className="grid h-10 w-10 place-items-center rounded-xl bg-gradient-to-br from-accent to-accent-2 text-sm font-extrabold text-white">
            BB
          </div>
          <div>
            <div className="font-bold">Bytebox</div>
            <div className="text-xs text-gray-500">{owner ? "Owner" : "Content admin"}</div>
          </div>
        </div>
        <nav className="flex gap-1 overflow-x-auto px-3 pb-3 lg:flex-col lg:overflow-visible">
          <NavLink href="/admin">Dashboard</NavLink>
          <NavLink href="/admin/channels">Channels</NavLink>
          <NavLink href="/admin/posts" count={counters.reports}>Posts</NavLink>
          {owner && (
            <>
              <NavLink href="/admin/approvals" count={counters.approvals}>Approvals</NavLink>
              <NavLink href="/admin/payments" count={counters.payments}>Payments</NavLink>
              <NavLink href="/admin/meta">Meta Pixel</NavLink>
              <NavLink href="/admin/users">Users</NavLink>
              <NavLink href="/admin/requests" count={counters.requests}>Requests</NavLink>
              <NavLink href="/admin/plans">Plans</NavLink>
              <NavLink href="/admin/admins">Admins</NavLink>
            </>
          )}
        </nav>
        <form action={signOut} className="hidden px-5 py-4 text-xs text-gray-500 lg:block">
          <div className="truncate">{email}</div>
          <button className="mt-1 font-semibold text-accent hover:underline">Sign out</button>
        </form>
      </aside>
      <main className="min-w-0 flex-1 px-4 py-6 sm:px-8">{children}</main>
    </div>
  );
}
