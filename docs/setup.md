# Bytebox — one-time setup

Everything below is done **once** in a browser. After that, all changes ship through pull requests.

## 1. GitHub repository secrets
GitHub → `cspreeinfotech-web/bytebox` → Settings → Secrets and variables → Actions → **New repository secret**.

| Secret | Value |
|---|---|
| `SUPABASE_PROJECT_REF` | `riynqwuaadnccvwamhoa` |
| `SUPABASE_URL` | `https://riynqwuaadnccvwamhoa.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_…` from Supabase → Project Settings → API Keys (publishable, safe for apps) |
| `SUPABASE_ACCESS_TOKEN` | Supabase → Account (top-right avatar) → Access Tokens → Generate new token |
| `SUPABASE_DB_PASSWORD` | Supabase → Project Settings → Database → **Reset database password**, copy it here |
| `ANDROID_KEYSTORE_BASE64` | from the keystore package Claude sent you |
| `ANDROID_KEYSTORE_PASSWORD` | 〃 |
| `ANDROID_KEY_ALIAS` | `bytebox` |
| `ANDROID_KEY_PASSWORD` | 〃 |

> Keep a backup of `bytebox-release.jks` and its passwords outside GitHub. Losing it means you can never update the app.

After adding the Supabase secrets, run **Actions → supabase-deploy → Run workflow** once.

## 2. Supabase Auth settings (Dashboard → Authentication)
- **Sign In / Providers → Allow anonymous sign-ins: ON** (guest accounts).
- **Email provider: ON.** "Confirm email": OFF gives the instant guest → account upgrade the app expects. If you turn it ON, users must click the email link before their email/password works.
- **URL Configuration → Redirect URLs:** add `com.bytebox.app://login-callback` and `com.bytebox.play://login-callback`. Site URL: `https://bytebox-ejim.vercel.app` (set automatically by the deploy workflow).
- Google provider: leave OFF for now — the app shows "Google sign-in is coming soon".

## 3. Make yourself the owner
1. Install the app and **create an account** with `cs.preeinfotech@gmail.com`.
2. Supabase → SQL Editor → run:
```sql
insert into public.admins (user_id, role)
select id, 'owner' from auth.users where email = 'cs.preeinfotech@gmail.com'
on conflict (user_id) do update set role = 'owner';
```

## 4. Website + admin (Vercel)
- Project `bytebox-ejim` (root directory `admin`) → **https://bytebox-ejim.vercel.app**; every merge to `main` deploys.
- Admin panel: **https://bytebox-ejim.vercel.app/admin** (sign in with your owner account).
- Ads download page for Meta ads: **https://bytebox-ejim.vercel.app/d**
