import type { Metadata } from "next";
import { DeletionForm } from "@/components/public-forms";
import { DocPage } from "@/components/site";
import { APP_NAME, SUPPORT_EMAIL } from "@/lib/env";

export const metadata: Metadata = { title: "Delete your account" };

export default function DeleteAccount() {
  return (
    <DocPage title={`Delete your ${APP_NAME} account`}>
      <p>You can delete your {APP_NAME} account and its data at any time — in the app, or with the form below.</p>
      <h2>In the app (fastest)</h2>
      <ol className="ml-5 list-decimal space-y-1">
        <li>Open {APP_NAME} and tap the <b>Profile</b> tab.</li>
        <li>Tap the account icon (top-right) → <b>Settings</b>.</li>
        <li>Tap <b>Delete Account</b> and confirm. Deletion happens immediately.</li>
      </ol>
      <h2>Request by form</h2>
      <p>No access to the app? Send a request. You can also ask us to <b>delete only some data</b> (for example your cloud files or one channel) instead of the whole account.</p>
      <DeletionForm />
      <h2>What is deleted</h2>
      <ul>
        <li>Your profile, email and login</li>
        <li>All files in your cloud</li>
        <li>Your channels, posts, videos and thumbnails</li>
        <li>Channel memberships, view history and consents</li>
      </ul>
      <h2>What is kept, and for how long</h2>
      <ul>
        <li><b>Payment records</b> (order number, plan, amount, date, UPI reference) — kept for up to <b>8 years</b> for tax and accounting law, no longer linked to your profile.</li>
        <li><b>Reports</b> you submitted about other content — kept up to 1 year for safety reviews, without your identity.</li>
        <li><b>Backups</b> — removed from rolling backups within 30 days.</li>
      </ul>
      <p>Questions: <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a></p>
    </DocPage>
  );
}
