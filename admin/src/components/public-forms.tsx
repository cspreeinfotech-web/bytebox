"use client";
import { useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { SUPABASE_KEY, SUPABASE_URL } from "@/lib/env";

// Called from the visitor's browser so the database sees the visitor's IP (rate limits, ad matching).
const anon = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
const field = "w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-sm outline-none focus:border-accent";

export function DeletionForm() {
  const [state, setState] = useState<"idle" | "busy" | "done">("idle");
  const [error, setError] = useState("");
  return state === "done" ? (
    <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-emerald-800">
      Request received. We will email you to confirm it is your account, then complete it within 30 days.
    </div>
  ) : (
    <form
      className="space-y-3 rounded-2xl border border-gray-200 bg-white p-5"
      onSubmit={async (e) => {
        e.preventDefault();
        const f = new FormData(e.currentTarget);
        setState("busy");
        setError("");
        const { error } = await anon().rpc("submit_deletion_request", {
          p_email: String(f.get("email")), p_scope: String(f.get("scope")), p_details: String(f.get("details") ?? ""),
        });
        if (error) { setError(error.message); setState("idle"); } else setState("done");
      }}
    >
      <label className="block text-sm font-medium">Email of your Bytebox account
        <input name="email" type="email" required className={field} /></label>
      <fieldset className="space-y-1 text-sm">
        <label className="flex items-center gap-2"><input type="radio" name="scope" value="account" defaultChecked /> Delete my whole account</label>
        <label className="flex items-center gap-2"><input type="radio" name="scope" value="some_data" /> Delete only some data</label>
      </fieldset>
      <label className="block text-sm font-medium">What should we delete? (optional)
        <textarea name="details" rows={3} className={field} placeholder="e.g. only my cloud files, or one channel" /></label>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <button disabled={state === "busy"} className="rounded-xl bg-accent px-5 py-2 font-semibold text-white disabled:opacity-50">
        {state === "busy" ? "Sending…" : "Send request"}
      </button>
    </form>
  );
}

export function ReportForm() {
  const [state, setState] = useState<"idle" | "busy" | "done">("idle");
  const [error, setError] = useState("");
  return state === "done" ? (
    <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-emerald-800">Thanks — our team will review this report.</div>
  ) : (
    <form
      className="space-y-3 rounded-2xl border border-gray-200 bg-white p-5"
      onSubmit={async (e) => {
        e.preventDefault();
        const f = new FormData(e.currentTarget);
        setState("busy");
        setError("");
        const { error } = await anon().rpc("submit_web_report", {
          p_reason: String(f.get("reason")), p_link: String(f.get("link")),
          p_details: String(f.get("details")), p_contact: String(f.get("contact") ?? ""),
        });
        if (error) { setError(error.message); setState("idle"); } else setState("done");
      }}
    >
      <label className="block text-sm font-medium">Reason
        <select name="reason" className={field} defaultValue="sexual">
          <option value="sexual">Sexual or nude content</option>
          <option value="violence">Violence or dangerous content</option>
          <option value="hate">Hate speech or harassment</option>
          <option value="copyright">Copyright — this is my content</option>
          <option value="spam">Spam, scam or misleading</option>
          <option value="other">Other</option>
        </select></label>
      <label className="block text-sm font-medium">Link to the post or channel
        <input name="link" required className={field} placeholder="https://…/p/…" /></label>
      <label className="block text-sm font-medium">Details
        <textarea name="details" required minLength={5} rows={4} className={field} /></label>
      <label className="block text-sm font-medium">Your email (so we can follow up)
        <input name="contact" type="email" className={field} /></label>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <button disabled={state === "busy"} className="rounded-xl bg-accent px-5 py-2 font-semibold text-white disabled:opacity-50">
        {state === "busy" ? "Sending…" : "Send report"}
      </button>
    </form>
  );
}
