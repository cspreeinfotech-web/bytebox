"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

export function NavLink({ href, children, count }: { href: string; children: ReactNode; count?: number | null }) {
  const path = usePathname();
  const active = href === "/admin" ? path === "/admin" : path.startsWith(href);
  return (
    <Link
      href={href}
      className={`flex items-center justify-between rounded-xl px-3 py-2 text-sm font-medium ${
        active ? "bg-accent/10 text-accent" : "text-gray-700 hover:bg-gray-100"
      }`}
    >
      <span>{children}</span>
      {count ? <span className="rounded-full bg-red-600 px-2 py-0.5 text-xs font-bold text-white">{count}</span> : null}
    </Link>
  );
}
