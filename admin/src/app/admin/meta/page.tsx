import { AdminShell } from "@/components/shell";
import { Card, PageHeader } from "@/components/ui";
import { requireAdmin } from "@/lib/admin";

export default async function Meta() {
  const { user, counters } = await requireAdmin({ owner: true });
  return (
    <AdminShell counters={counters} email={user.email}>
      <PageHeader title="Meta Pixel" />
      <Card>Meta Pixel, Conversions API and the ads APK upload arrive in Stage 8.</Card>
    </AdminShell>
  );
}
