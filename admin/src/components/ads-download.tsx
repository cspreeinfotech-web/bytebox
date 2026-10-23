"use client";
import Script from "next/script";
import { useEffect } from "react";
import { createClient } from "@supabase/supabase-js";
import { SUPABASE_KEY, SUPABASE_URL } from "@/lib/env";

declare global {
  interface Window { fbq?: (...args: unknown[]) => void }
}

function cookie(name: string) {
  return document.cookie.split("; ").find((c) => c.startsWith(`${name}=`))?.split("=")[1] ?? null;
}

/** Meta Pixel (PageView + ViewContent) and ad-click capture for install matching. */
export function AdsDownload({ pixelId, apkUrl }: { pixelId: string | null; apkUrl: string | null }) {
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const fbclid = params.get("fbclid");
    // _fbp is set by the pixel shortly after load.
    const t = setTimeout(() => {
      createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } })
        .rpc("record_ad_click", { p_fbclid: fbclid, p_fbp: cookie("_fbp"), p_landing_url: window.location.href })
        .then(() => undefined);
    }, 1200);
    return () => clearTimeout(t);
  }, []);

  return (
    <>
      {pixelId && (
        <Script id="meta-pixel" strategy="afterInteractive">{`
!function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?
n.callMethod.apply(n,arguments):n.queue.push(arguments)};if(!f._fbq)f._fbq=n;
n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];t=b.createElement(e);t.async=!0;
t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}(window,
document,'script','https://connect.facebook.net/en_US/fbevents.js');
fbq('init', '${pixelId}');
fbq('track', 'PageView');
fbq('track', 'ViewContent', {content_name: 'Bytebox APK', content_type: 'product'});
`}</Script>
      )}
      {apkUrl ? (
        <a
          href={apkUrl}
          onClick={() => window.fbq?.("trackCustom", "DownloadAPK")}
          className="inline-flex items-center justify-center rounded-2xl bg-gradient-to-r from-accent to-accent-2 px-8 py-4 text-lg font-bold text-white shadow-lg shadow-accent/30"
        >
          Download Bytebox (Android)
        </a>
      ) : (
        <span className="inline-flex rounded-2xl bg-white/10 px-8 py-4 font-semibold text-white/70">Download coming soon</span>
      )}
    </>
  );
}
