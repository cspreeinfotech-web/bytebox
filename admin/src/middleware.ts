import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { ADMIN, ADMIN_SLUG } from "@/lib/admin-path";
import { SUPABASE_KEY, SUPABASE_URL } from "@/lib/env";

/**
 * The admin panel is served at ADMIN (e.g. /workspace-1a2b3c4d) and rewritten to the app/admin pages.
 * When a secret slug is set, the plain /admin address answers 404 so the panel can't be found by guessing.
 * Also keeps the admin session fresh and sends signed-out visitors to the login page.
 */
export async function middleware(request: NextRequest) {
  const path = request.nextUrl.pathname;
  const hidden = ADMIN_SLUG !== "admin";
  const inPanel = path === ADMIN || path.startsWith(ADMIN + "/");

  if (hidden && (path === "/admin" || path.startsWith("/admin/"))) {
    return NextResponse.rewrite(new URL("/__not_found", request.url));
  }
  if (!inPanel) return NextResponse.next();

  // Public URL → internal app/admin route.
  const internal = request.nextUrl.clone();
  internal.pathname = "/admin" + path.slice(ADMIN.length);
  let response = hidden ? NextResponse.rewrite(internal, { request }) : NextResponse.next({ request });
  if (!SUPABASE_URL || !SUPABASE_KEY) return response;

  const supabase = createServerClient(SUPABASE_URL, SUPABASE_KEY, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(toSet) {
        toSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = hidden ? NextResponse.rewrite(internal, { request }) : NextResponse.next({ request });
        toSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const { data } = await supabase.auth.getUser();
  if (!data.user && path !== ADMIN + "/login") {
    const url = request.nextUrl.clone();
    url.pathname = ADMIN + "/login";
    url.search = "";
    return NextResponse.redirect(url);
  }
  return response;
}

// Run on every page (not static files); the function returns early for non-admin paths.
export const config = { matcher: ["/((?!_next/|favicon.ico|.*\\.[A-Za-z0-9]+$).*)"] };
