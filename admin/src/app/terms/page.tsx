import type { Metadata } from "next";
import { DocPage } from "@/components/site";
import { SUPPORT_EMAIL } from "@/lib/env";

export const metadata: Metadata = { title: "Terms, Refunds and Community Guidelines" };

export default function Terms() {
  return (
    <DocPage title="Terms of Use" updated="23 October 2026">
      <h2 id="terms">1. Using Bytebox</h2>
      <p>By using Bytebox you agree to these terms. You must be 18 or older. You are responsible for the activity on your account and for keeping your password safe. Guest accounts can be lost if you uninstall the app or log out — create an account to keep your data.</p>
      <h2>2. Premium plans</h2>
      <p>Premium plans give access to full premium videos, up to 2 TB of cloud storage and downloads for the period shown when you buy (for example 7, 30, 180 or 365 days). Plans are one-time payments made through your own UPI app; they do <b>not</b> renew automatically. Buying again while a plan is active adds the new days to the end of your current plan. Prices are in Indian Rupees and include applicable taxes.</p>
      <p>Payments are verified. If a payment cannot be confirmed with our bank, or is reversed, we may end the plan it activated.</p>
      <h2>3. Your content</h2>
      <p>You keep ownership of files you upload and content you post. You give us the permission we need to store, process and show it to the audiences you choose. Do not upload anything you do not have the right to share. Files are limited to 50 MB each.</p>
      <h2>4. Termination</h2>
      <p>You can delete your account at any time. We may suspend accounts that break these terms or the law.</p>
      <h2>5. Liability</h2>
      <p>Bytebox is provided &quot;as is&quot;. Keep your own copies of important files. To the extent permitted by law, our total liability is limited to the amount you paid us in the last 3 months.</p>
      <h2>6. Law</h2>
      <p>These terms are governed by the laws of India, with courts in Gujarat having jurisdiction.</p>

      <h2 id="refund">Refund Policy</h2>
      <ul>
        <li>If money was taken from your account but your plan did not activate, keep the <b>order number</b> shown in the app and email us. We verify it against our bank and either activate the plan or refund the full amount within 7 working days.</li>
        <li>If you were charged twice for the same order, the duplicate is refunded in full.</li>
        <li>Because plans start immediately, we do not refund a plan after it has been activated and used, except where required by law or where the service was unavailable for most of the plan period.</li>
        <li>Refunds go back to the same UPI account that paid.</li>
      </ul>

      <h2 id="community">Community Guidelines</h2>
      <p>Channels are reviewed before they appear. These are not allowed anywhere on Bytebox:</p>
      <ul>
        <li>Sexual or nude content, and any content involving minors in a sexual or harmful way.</li>
        <li>Violence, threats, self-harm encouragement or dangerous activities.</li>
        <li>Hate speech, harassment or bullying.</li>
        <li>Content you do not own or have permission to share.</li>
        <li>Spam, scams, misleading content or fake giveaways.</li>
        <li>Anything illegal in India.</li>
      </ul>
      <p>Use <b>Report</b> on any post or channel, or our <a href="/report-content">report form</a>. We review reports and may remove content, disable channels or close accounts.</p>

      <h2 id="dmca">Copyright (takedown requests)</h2>
      <p>If you believe content on Bytebox infringes your copyright, send us: your name and contact details, a description of your work, the link to the content (bytebox link like <code>/p/…</code>), and a statement that you are the owner or authorised to act. Use the <a href="/report-content">report form</a> (reason: Copyright) or email <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. We remove infringing content promptly and may close repeat infringers&apos; accounts.</p>

      <h2>Contact</h2>
      <p><a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a></p>
    </DocPage>
  );
}
