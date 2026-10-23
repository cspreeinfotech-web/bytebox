import type { Metadata } from "next";
import { AdsDownload } from "@/components/ads-download";
import { publicClient } from "@/lib/supabase/public";
import { SUPABASE_URL, isConfigured } from "@/lib/env";

export const metadata: Metadata = { title: "Download Bytebox", robots: { index: false } };
export const revalidate = 60;

const steps = [
  "Tap Download and open the file when it finishes.",
  "If Android asks, allow installs from your browser (Settings → Install unknown apps).",
  "Open Bytebox — you're in as a guest straight away.",
];

export default async function DownloadPage() {
  let pixel: string | null = null;
  let apk: string | null = null;
  if (isConfigured) {
    const { data } = await publicClient().from("site_settings").select("meta_pixel_id, ads_apk_path").eq("id", 1).maybeSingle();
    pixel = data?.meta_pixel_id ?? null;
    if (data?.ads_apk_path) apk = `${SUPABASE_URL}/storage/v1/object/public/downloads/${data.ads_apk_path}`;
  }
  return (
    <main className="min-h-screen bg-ink px-4 py-12 text-white">
      <div className="mx-auto max-w-md text-center">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon.png" alt="Bytebox" className="mx-auto h-28 w-28 rounded-[1.75rem] shadow-2xl shadow-accent/40" />
        <h1 className="mt-6 text-3xl font-extrabold">Bytebox</h1>
        <p className="mt-2 text-white/70">Your private cloud + creator videos. Watch trailers free; Premium from ₹49.</p>
        <div className="mt-8"><AdsDownload pixelId={pixel} apkUrl={apk} /></div>
        <ol className="mt-10 space-y-3 text-left text-sm text-white/80">
          {steps.map((s, i) => (
            <li key={s} className="flex gap-3"><span className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-accent text-xs font-bold">{i + 1}</span>{s}</li>
          ))}
        </ol>
        <p className="mt-10 text-xs text-white/40">18+ only. By installing you agree to our <a className="underline" href="/terms">Terms</a> and <a className="underline" href="/privacy">Privacy Policy</a>.</p>
      </div>
    </main>
  );
}
