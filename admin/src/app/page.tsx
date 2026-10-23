import Link from "next/link";
import { SiteFooter, SiteHeader } from "@/components/site";
import { publicClient } from "@/lib/supabase/public";
import { SUPABASE_URL, isConfigured } from "@/lib/env";

export const revalidate = 300;

const features = [
  ["Your own cloud", "Keep photos, videos and documents safe and reach them from any phone. Up to 2 TB with Premium."],
  ["Folders that make sense", "Upload, rename, move and organise files the way you think. Open anything with one tap."],
  ["Creator channels", "Follow channels you love and watch new videos in your feed."],
  ["Pay your way", "Premium plans start at ₹49. Pay with any UPI app — no cards, no auto-debit."],
];

export default async function Home() {
  let apk: string | null = null;
  if (isConfigured) {
    const { data } = await publicClient().from("site_settings").select("organic_apk_path").eq("id", 1).maybeSingle();
    if (data?.organic_apk_path) apk = `${SUPABASE_URL}/storage/v1/object/public/downloads/${data.organic_apk_path}`;
  }
  return (
    <div className="min-h-screen bg-white">
      <SiteHeader />
      <section className="bg-ink text-white">
        <div className="mx-auto grid max-w-5xl items-center gap-10 px-4 py-20 md:grid-cols-2">
          <div>
            <h1 className="text-4xl font-extrabold leading-tight md:text-5xl">
              Your files,<br />safe in <span className="bg-gradient-to-r from-accent to-accent-2 bg-clip-text text-transparent">your own cloud</span>.
            </h1>
            <p className="mt-5 text-lg text-white/70">
              Bytebox is personal cloud storage for your phone — plus videos from creator channels you follow.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              {apk ? (
                <a href={apk} className="rounded-xl bg-gradient-to-r from-accent to-accent-2 px-6 py-3 font-semibold">Download for Android</a>
              ) : (
                <span className="rounded-xl bg-white/10 px-6 py-3 font-semibold text-white/70">Android app coming soon</span>
              )}
              <Link href="/terms" className="rounded-xl border border-white/20 px-6 py-3 font-semibold">How it works</Link>
            </div>
          </div>
          <div className="flex justify-center">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/icon.png" alt="Bytebox" className="h-56 w-56 rounded-[3rem] shadow-2xl shadow-accent/40" />
          </div>
        </div>
      </section>
      <section className="mx-auto grid max-w-5xl gap-6 px-4 py-16 sm:grid-cols-2">
        {features.map(([t, d]) => (
          <div key={t} className="rounded-2xl border border-gray-200 p-6">
            <h2 className="text-lg font-bold">{t}</h2>
            <p className="mt-2 text-gray-600">{d}</p>
          </div>
        ))}
      </section>
      <SiteFooter />
    </div>
  );
}
