import Link from "next/link";
import type { ReactNode } from "react";
import { APP_NAME, SUPPORT_EMAIL } from "@/lib/env";

export function SiteHeader() {
  return (
    <header className="border-b border-white/10 bg-ink text-white">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-4">
        <Link href="/" className="flex items-center gap-2 font-bold">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/icon.png" alt="" className="h-8 w-8 rounded-lg" /> {APP_NAME}
        </Link>
        <nav className="flex gap-4 text-sm text-white/70">
          <Link href="/privacy" className="hover:text-white">Privacy</Link>
          <Link href="/terms" className="hover:text-white">Terms</Link>
          <Link href="/delete-account" className="hover:text-white">Delete account</Link>
        </nav>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="border-t border-gray-200 bg-white">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-8 text-sm text-gray-500">
        <div>© {new Date().getFullYear()} {APP_NAME}. Made in India.</div>
        <div className="flex flex-wrap gap-4">
          <Link href="/privacy">Privacy Policy</Link>
          <Link href="/terms">Terms</Link>
          <Link href="/terms#refund">Refunds</Link>
          <Link href="/terms#community">Community Guidelines</Link>
          <Link href="/report-content">Report content</Link>
          <Link href="/delete-account">Delete account</Link>
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
        </div>
      </div>
    </footer>
  );
}

/** Simple readable page for policies and forms. */
export function DocPage({ title, updated, children }: { title: string; updated?: string; children: ReactNode }) {
  return (
    <div className="min-h-screen bg-gray-50">
      <SiteHeader />
      <main className="mx-auto max-w-3xl px-4 py-10">
        <h1 className="text-3xl font-bold text-gray-900">{title}</h1>
        {updated && <p className="mt-1 text-sm text-gray-500">Last updated: {updated}</p>}
        <div className="prose-doc mt-8 space-y-4 text-gray-700 [&_h2]:mt-8 [&_h2]:text-xl [&_h2]:font-bold [&_h2]:text-gray-900 [&_li]:ml-5 [&_li]:list-disc [&_a]:text-accent [&_a]:underline">
          {children}
        </div>
      </main>
      <SiteFooter />
    </div>
  );
}
