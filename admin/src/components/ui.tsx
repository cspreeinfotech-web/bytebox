import Link from "next/link";
import type { ReactNode } from "react";

export const btn = {
  primary: "inline-flex items-center justify-center gap-2 rounded-xl bg-accent px-4 py-2 text-sm font-semibold text-white hover:bg-accent-dark disabled:opacity-50",
  secondary: "inline-flex items-center justify-center gap-2 rounded-xl border border-gray-300 bg-white px-4 py-2 text-sm font-semibold text-gray-800 hover:bg-gray-50",
  danger: "inline-flex items-center justify-center gap-2 rounded-xl bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700",
  success: "inline-flex items-center justify-center gap-2 rounded-xl bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700",
  small: "inline-flex items-center gap-1 rounded-lg border border-gray-300 bg-white px-2.5 py-1 text-xs font-semibold text-gray-700 hover:bg-gray-50",
};

export const input =
  "w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-sm outline-none focus:border-accent focus:ring-2 focus:ring-accent/20";

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`rounded-2xl border border-gray-200 bg-white p-5 shadow-sm ${className}`}>{children}</div>;
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-gray-500">{subtitle}</p>}
      </div>
      {actions}
    </div>
  );
}

const badgeColors: Record<string, string> = {
  green: "bg-emerald-50 text-emerald-700 ring-emerald-200",
  amber: "bg-amber-50 text-amber-700 ring-amber-200",
  red: "bg-red-50 text-red-700 ring-red-200",
  gray: "bg-gray-100 text-gray-700 ring-gray-200",
  violet: "bg-violet-50 text-violet-700 ring-violet-200",
  blue: "bg-sky-50 text-sky-700 ring-sky-200",
};

export function Badge({ children, color = "gray" }: { children: ReactNode; color?: keyof typeof badgeColors }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold ring-1 ring-inset ${badgeColors[color]}`}>
      {children}
    </span>
  );
}

export function Stat({ label, value, href, tone }: { label: string; value: ReactNode; href?: string; tone?: "amber" }) {
  const body = (
    <div className={`rounded-2xl border bg-white p-5 shadow-sm ${tone === "amber" ? "border-amber-300 bg-amber-50" : "border-gray-200"}`}>
      <div className="text-sm text-gray-500">{label}</div>
      <div className="mt-1 text-2xl font-bold text-gray-900">{value}</div>
    </div>
  );
  return href ? <Link href={href} className="block hover:opacity-90">{body}</Link> : body;
}

export function Flash({ ok, err }: { ok?: string; err?: string }) {
  if (!ok && !err) return null;
  return (
    <div className={`mb-5 rounded-xl border px-4 py-3 text-sm font-medium ${err ? "border-red-200 bg-red-50 text-red-700" : "border-emerald-200 bg-emerald-50 text-emerald-700"}`}>
      {err ?? ok}
    </div>
  );
}

export const statusColor = (s: string): keyof typeof badgeColors =>
  ({ success: "green", approved: "green", active: "green", published: "green", pending: "amber", initiated: "amber",
     open: "amber", failed: "red", rejected: "red", revoked: "red", removed: "red", disabled: "gray", cancelled: "gray",
     draft: "gray", dismissed: "gray", actioned: "violet" } as Record<string, keyof typeof badgeColors>)[s] ?? "gray";

export function Empty({ text = "No Record Found" }: { text?: string }) {
  return <div className="py-12 text-center text-sm text-gray-500">{text}</div>;
}
