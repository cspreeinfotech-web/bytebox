"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

/** Uploads an APK straight from the browser to the public "downloads" bucket (owner-only by RLS). */
export function ApkUpload({ kind, current }: { kind: "ads" | "organic"; current: string | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");
  return (
    <div className="rounded-xl border border-gray-200 p-4">
      <div className="font-semibold">{kind === "ads" ? "Ads APK (shown on /d)" : "Organic APK (website home page)"}</div>
      <div className="mb-3 break-all text-xs text-gray-500">{current ?? "Not uploaded yet"}</div>
      <input
        type="file"
        accept=".apk,application/vnd.android.package-archive"
        disabled={busy}
        onChange={async (e) => {
          const file = e.target.files?.[0];
          if (!file) return;
          if (!window.confirm(`Upload ${file.name} as the ${kind} APK?`)) return;
          setBusy(true);
          setMsg("Uploading…");
          const supabase = createClient();
          const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "");
          const path = `${kind}/Bytebox${kind === "ads" ? "-ads" : ""}-${stamp}.apk`;
          const up = await supabase.storage.from("downloads").upload(path, file, {
            contentType: "application/vnd.android.package-archive", upsert: false,
          });
          if (up.error) { setMsg(up.error.message); setBusy(false); return; }
          const col = kind === "ads" ? { ads_apk_path: path, ads_apk_uploaded_at: new Date().toISOString() } : { organic_apk_path: path };
          const { error } = await supabase.from("site_settings").update(col).eq("id", 1);
          setMsg(error ? error.message : "Uploaded. The download page now uses this file.");
          setBusy(false);
          router.refresh();
        }}
        className="text-sm"
      />
      {msg && <p className="mt-2 text-sm text-gray-600">{msg}</p>}
    </div>
  );
}
