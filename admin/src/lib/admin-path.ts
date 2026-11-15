/**
 * Public URL of the admin panel. Set ADMIN_SLUG in Vercel (server-only, never committed) to move the
 * panel to a hard-to-guess address such as /workspace-1a2b3c4d; /admin then answers 404.
 * Without ADMIN_SLUG the panel stays at /admin. Internally the pages still live in app/admin.
 */
const raw = (process.env.ADMIN_SLUG ?? "").trim().replace(/^\/+|\/+$/g, "");
export const ADMIN_SLUG = /^[A-Za-z0-9_-]{8,64}$/.test(raw) ? raw : "admin";
export const ADMIN = `/${ADMIN_SLUG}`;
