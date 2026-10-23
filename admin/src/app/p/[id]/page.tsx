import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site";
import { publicClient } from "@/lib/supabase/public";
import { isConfigured } from "@/lib/env";

type Preview = { title: string; channel: string; is_premium: boolean; kind: string } | null;

async function load(id: string): Promise<Preview> {
  if (!isConfigured || !/^[0-9a-f-]{36}$/i.test(id)) return null;
  const { data } = await publicClient().rpc("public_post_preview", { p_post_id: id });
  return (data as Preview) ?? null;
}

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const p = await load((await params).id);
  return { title: p ? p.title : "Watch on Bytebox", robots: { index: false } };
}

export default async function SharedPost({ params }: { params: Promise<{ id: string }> }) {
  const p = await load((await params).id);
  return (
    <div className="min-h-screen bg-gray-50">
      <SiteHeader />
      <main className="mx-auto max-w-xl px-4 py-16 text-center">
        <div className="rounded-3xl border border-gray-200 bg-white p-8 shadow-sm">
          <div className="text-sm font-semibold uppercase tracking-wide text-accent">{p ? p.channel : "Bytebox"}</div>
          <h1 className="mt-2 text-2xl font-bold">{p ? p.title : "This post is available in the Bytebox app"}</h1>
          {p?.is_premium && <div className="mt-3 inline-block rounded-full bg-premium px-3 py-1 text-xs font-bold text-ink">Premium</div>}
          <p className="mt-4 text-gray-600">Open it in the Bytebox app to {p?.kind === "photo" ? "view" : "watch"}.</p>
          <Link href="/" className="mt-6 inline-block rounded-xl bg-gradient-to-r from-accent to-accent-2 px-6 py-3 font-semibold text-white">Get Bytebox</Link>
        </div>
      </main>
      <SiteFooter />
    </div>
  );
}
