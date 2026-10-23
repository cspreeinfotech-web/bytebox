import type { Metadata } from "next";
import { DocPage } from "@/components/site";
import { SUPPORT_EMAIL } from "@/lib/env";

export const metadata: Metadata = { title: "Privacy Policy" };

export default function Privacy() {
  return (
    <DocPage title="Privacy Policy" updated="23 October 2026">
      <p>This policy explains what Bytebox (&quot;we&quot;) collects when you use the Bytebox Android app and website, why, and the choices you have. Bytebox is intended only for people aged 18 and over.</p>
      <h2>What we collect</h2>
      <ul>
        <li><b>Account data:</b> a random account ID created when you first open the app (guest account), and — if you create an account — your email address and a hashed password.</li>
        <li><b>Install data:</b> a random install ID, the install source (for example whether the app was downloaded from one of our ads), basic device information (manufacturer, model, Android version) and the IP address and browser/app user agent of the request.</li>
        <li><b>Your content:</b> files you upload to your cloud, and channels and posts you create, with their titles and descriptions.</li>
        <li><b>Usage:</b> which posts you view (to count views), channels you join, reports you submit.</li>
        <li><b>Payments:</b> the plan, amount, order number and the UPI transaction reference returned by your UPI app. We never see or store your bank account, card or UPI PIN — payments happen inside your own UPI app.</li>
        <li><b>Consents:</b> the version of these documents you accepted and when.</li>
      </ul>
      <h2>Why we use it</h2>
      <ul>
        <li>To run the service: sign you in, store your files, show content you are allowed to see, and activate plans you buy.</li>
        <li>To prevent fraud and abuse: verify payments, limit repeated activations, review reports.</li>
        <li>To measure our advertising: when you install from our Meta (Facebook/Instagram) ads, we send Meta limited event data (install, registration, purchase value) using the Meta Conversions API. Email addresses and IDs are hashed (SHA-256) before they are sent.</li>
      </ul>
      <h2>Who we share it with</h2>
      <ul>
        <li><b>Supabase</b> (database, storage and authentication hosting) and <b>Vercel</b> (website hosting) process data on our behalf.</li>
        <li><b>Meta Platforms</b> receives the advertising events described above.</li>
        <li>Authorities, when required by Indian law.</li>
      </ul>
      <p>We do not sell your personal data. The Google Play version of the app does not use the advertising ID.</p>
      <h2>Your files are private</h2>
      <p>Files in your cloud are stored in a private bucket and are only accessible to your account through short-lived links (valid for one hour).</p>
      <h2>Retention</h2>
      <p>We keep your data while your account exists. When you delete your account, we delete your profile, cloud files, channels and posts. Payment records are kept for up to 8 years to meet tax and accounting rules, without your profile attached. Server logs are kept for up to 90 days.</p>
      <h2>Your rights</h2>
      <p>You can access and correct your data in the app, download your files, and delete your account from <b>Profile → Settings → Delete Account</b> or via our <a href="/delete-account">account deletion page</a>. Under the Digital Personal Data Protection Act, 2023 you may also contact our grievance officer.</p>
      <h2>Contact / Grievance officer</h2>
      <p>Email <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. We respond within 30 days.</p>
    </DocPage>
  );
}
