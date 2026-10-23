import { DIRECT_PACKAGE, PLAY_PACKAGE } from "@/lib/env";

// Release certificate (see docs/setup.md). Add Play App Signing's SHA-256 via ANDROID_CERT_SHA256 (comma separated).
const DEFAULT_CERT = "8C:8C:F9:7A:74:C0:1F:7D:D0:3C:46:04:28:80:D1:B9:77:F8:A1:D7:B7:E1:93:33:B5:8A:EF:61:DC:BF:09:0D";

export const dynamic = "force-static";

export function GET() {
  const certs = (process.env.ANDROID_CERT_SHA256 ?? DEFAULT_CERT).split(",").map((c) => c.trim()).filter(Boolean);
  const body = [DIRECT_PACKAGE, PLAY_PACKAGE].map((pkg) => ({
    relation: ["delegate_permission/common.handle_all_urls"],
    target: { namespace: "android_app", package_name: pkg, sha256_cert_fingerprints: certs },
  }));
  return Response.json(body, { headers: { "Cache-Control": "public, max-age=3600" } });
}
