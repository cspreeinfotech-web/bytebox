"use client";
import { useState, type FormEvent, type ReactNode } from "react";
import { useFormStatus } from "react-dom";

const input = "w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-sm outline-none focus:border-accent focus:ring-2 focus:ring-accent/20";
const primary = "inline-flex items-center justify-center rounded-xl bg-accent px-4 py-2 text-sm font-semibold text-white hover:bg-accent-dark disabled:opacity-50";

function Submit({ children, className = primary }: { children: ReactNode; className?: string }) {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending} className={className}>{pending ? "Saving…" : children}</button>;
}

export function durationHelper(days: number) {
  if (!days || days < 1) return "";
  if (days % 365 === 0) return `= ${days / 365} year${days === 365 ? "" : "s"}`;
  if (days === 180) return "= 6 months";
  if (days % 30 === 0) return `= ${days / 30} month${days === 30 ? "" : "s"}`;
  if (days % 7 === 0) return `= ${days / 7} week${days === 7 ? "" : "s"}`;
  return `= ${days} days`;
}

export type PlanValues = {
  id?: number; code?: string; name?: string; price_inr?: number; duration_days?: number; perks?: string[];
  badge?: string | null; position?: number; active?: boolean; free_eligible?: boolean;
};

/** Plan editor. Confirms when price/duration change or the plan is hidden. */
export function PlanForm({ action, plan, isNew }: { action: (f: FormData) => void; plan?: PlanValues; isNew?: boolean }) {
  const [days, setDays] = useState<number>(plan?.duration_days ?? 30);
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    if (isNew || !plan) return;
    const f = new FormData(e.currentTarget);
    const changed = Number(f.get("price_inr")) !== plan.price_inr || Number(f.get("duration_days")) !== plan.duration_days;
    const hidden = plan.active && f.get("active") !== "on";
    if ((changed || hidden) && !window.confirm(
      "Existing subscribers keep their current plan until it ends. New buyers see the new price/duration.\n\nSave changes?")) {
      e.preventDefault();
    }
  };
  return (
    <form action={action} onSubmit={onSubmit} className="grid gap-3 sm:grid-cols-6">
      {plan?.id && <input type="hidden" name="id" value={plan.id} />}
      <label className="text-xs font-medium">Code
        {isNew ? <input name="code" required pattern="[a-z0-9_-]{2,30}" placeholder="festival" className={input} />
               : <input value={plan?.code} readOnly className={`${input} bg-gray-50 font-mono text-gray-500`} />}</label>
      <label className="text-xs font-medium sm:col-span-2">Name<input name="name" required defaultValue={plan?.name} className={input} /></label>
      <label className="text-xs font-medium">Price ₹<input name="price_inr" type="number" min={1} required defaultValue={plan?.price_inr} className={input} /></label>
      <label className="text-xs font-medium">Duration (days)
        <input name="duration_days" type="number" min={1} required defaultValue={plan?.duration_days ?? 30}
          onChange={(e) => setDays(Number(e.target.value))} className={input} />
        <span className="mt-1 block text-[11px] text-gray-500">{durationHelper(days)}</span></label>
      <label className="text-xs font-medium">Badge<input name="badge" defaultValue={plan?.badge ?? ""} placeholder="Best value" className={input} /></label>
      <label className="text-xs font-medium sm:col-span-3">Perks (one per line)
        <textarea name="perks" rows={3} defaultValue={(plan?.perks ?? ["Full premium videos", "2 TB cloud storage", "Downloads"]).join("\n")} className={input} /></label>
      <label className="text-xs font-medium">Order<input name="position" type="number" defaultValue={plan?.position ?? 0} className={input} /></label>
      <div className="flex flex-col justify-center gap-2 text-sm sm:col-span-2">
        <label className="flex items-center gap-2"><input type="checkbox" name="active" defaultChecked={plan?.active ?? true} /> Show in app</label>
        <label className="flex items-center gap-2"><input type="checkbox" name="free_eligible" defaultChecked={plan?.free_eligible ?? true} /> Free (eligible for free plans)</label>
      </div>
      <div className="sm:col-span-6"><Submit>{isNew ? "Add plan" : "Save plan"}</Submit></div>
    </form>
  );
}

/** UPI editor. Confirms the account new payments will go to. */
export function UpiForm({ action, current }: {
  action: (f: FormData) => void;
  current: { upi_id: string | null; payee_name: string | null; enabled: boolean; activation_mode: string };
}) {
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    const f = new FormData(e.currentTarget);
    if (!window.confirm(`New payments will go to ${f.get("upi_id")} (${f.get("payee_name")}). Continue?`)) e.preventDefault();
  };
  return (
    <form action={action} onSubmit={onSubmit} className="grid gap-3 sm:grid-cols-2">
      <label className="text-xs font-medium">New UPI ID
        <input name="upi_id" required defaultValue={current.upi_id ?? ""} placeholder="yourbusiness@okaxis" pattern="[A-Za-z0-9._\-]{2,200}@[A-Za-z0-9.\-]{2,64}" className={`${input} font-mono`} /></label>
      <label className="text-xs font-medium">Payee name (exactly as your bank shows it)
        <input name="payee_name" required minLength={2} defaultValue={current.payee_name ?? ""} className={input} /></label>
      <label className="text-xs font-medium">Activation mode
        <select name="activation_mode" defaultValue={current.activation_mode} className={input}>
          <option value="instant">Instant — plan starts when the UPI app reports success (with safeguards)</option>
          <option value="manual">Manual — every payment waits until you Mark paid</option>
        </select></label>
      <label className="flex items-center gap-2 pt-5 text-sm"><input type="checkbox" name="enabled" defaultChecked={current.enabled} /> Payments enabled</label>
      <div className="sm:col-span-2"><Submit>Save UPI settings</Submit></div>
    </form>
  );
}

/** Select + confirm (used for Free plans). */
export function ConfirmSelect({ action, name, value, options, message, button }: {
  action: (f: FormData) => void; name: string; value: string; options: [string, string][]; message: string; button: string;
}) {
  return (
    <form action={action} onSubmit={(e) => {
      const v = new FormData(e.currentTarget).get(name);
      if (v !== "none" && !window.confirm(message)) e.preventDefault();
    }} className="flex flex-wrap items-center gap-3">
      <select name={name} defaultValue={value} className={`${input} w-auto`}>
        {options.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
      </select>
      <Submit>{button}</Submit>
    </form>
  );
}
