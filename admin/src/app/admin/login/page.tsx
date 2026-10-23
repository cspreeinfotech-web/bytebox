import { signIn } from "@/app/admin/actions";
import { Flash, btn, input } from "@/components/ui";
import { one, type SP } from "@/lib/admin";

export default async function Login({ searchParams }: { searchParams: SP }) {
  const sp = await searchParams;
  return (
    <div className="grid min-h-screen place-items-center px-4">
      <form action={signIn} className="w-full max-w-sm rounded-2xl border border-gray-200 bg-white p-8 shadow-sm">
        <div className="mb-6 flex items-center gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-xl bg-gradient-to-br from-accent to-accent-2 font-extrabold text-white">BB</div>
          <div>
            <div className="text-lg font-bold">Bytebox Admin</div>
            <div className="text-xs text-gray-500">Sign in with your Bytebox account</div>
          </div>
        </div>
        <Flash err={one(sp.err) || undefined} />
        <label className="mb-1 block text-sm font-medium">Email</label>
        <input name="email" type="email" required className={`${input} mb-4`} autoComplete="email" />
        <label className="mb-1 block text-sm font-medium">Password</label>
        <input name="password" type="password" required className={`${input} mb-6`} autoComplete="current-password" />
        <button className={`${btn.primary} w-full`}>Sign in</button>
      </form>
    </div>
  );
}
