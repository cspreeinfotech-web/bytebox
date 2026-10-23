# Bytebox

Guest-first Android app for personal **cloud storage** plus creator **video channels**, with time-based Premium plans paid through the user's own UPI app.

| Folder | What lives there |
|---|---|
| `/mobile` | Flutter app (Android) + Kotlin MethodChannels. Flavors: `direct` (`com.bytebox.app`) and `play` (`com.bytebox.play`). |
| `/admin` | Next.js (App Router, TypeScript, Tailwind) — admin panel + public website, deployed on Vercel. |
| `/supabase` | Migrations, Edge Functions, SQL tests. Applied **only** by GitHub Actions. |
| `/docs` | Setup notes, store assets, Play Console answers. |

## Project constants

| Key | Value |
|---|---|
| APP_NAME | Bytebox |
| SHORT_CODE | BB |
| DIRECT_PACKAGE | com.bytebox.app |
| PLAY_PACKAGE | com.bytebox.play |
| THEME | A — Royal Violet |
| START_MODE | PAID |
| Supabase project ref | `riynqwuaadnccvwamhoa` (Mumbai, ap-south-1) |

## Rules

- Every database change is a migration in `supabase/migrations`, applied by the `supabase-deploy` workflow. Never `db reset` on the remote project.
- Every access rule is enforced in the database (RLS + `security definer` functions), not only in the app.
- No secrets in the repo. All credentials live in **GitHub → Settings → Secrets and variables → Actions** and in Vercel env vars.

## Required GitHub secrets

`SUPABASE_PROJECT_REF`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

## GitHub Actions minutes

Private repositories have a limited number of free Actions minutes per month. If jobs fail with no runner assigned or stay queued, check **Settings → Billing and plans** on GitHub, or make the repository public.
