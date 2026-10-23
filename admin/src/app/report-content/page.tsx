import type { Metadata } from "next";
import { ReportForm } from "@/components/public-forms";
import { DocPage } from "@/components/site";

export const metadata: Metadata = { title: "Report content" };

export default function ReportContent() {
  return (
    <DocPage title="Report content">
      <p>Seen something on Bytebox that breaks our <a href="/terms#community">Community Guidelines</a> or your copyright? Tell us here. You can also tap <b>Report</b> on any post in the app.</p>
      <ReportForm />
    </DocPage>
  );
}
