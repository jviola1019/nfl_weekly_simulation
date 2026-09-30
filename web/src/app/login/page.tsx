import { login } from "./actions";

export const metadata = { title: "Sign in", robots: { index: false } };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return (
    <div className="max-w-sm">
      <h1 className="text-2xl font-semibold">Sign in to the desk</h1>
      <p className="mt-2 text-ink-2">The desk is private. Public pages never show stakes.</p>
      {error ? (
        <p role="alert" className="mt-4 text-crit">That email and password did not match, or sign-in is paused after repeated attempts.</p>
      ) : null}
      <form action={login} className="mt-6 space-y-4">
        <label className="block">
          <span className="text-sm text-ink-2">Email</span>
          <input name="email" type="email" autoComplete="username" required className="mt-1 block w-full rounded-[3px] border border-rule bg-surface px-3 py-2" />
        </label>
        <label className="block">
          <span className="text-sm text-ink-2">Password</span>
          <input name="password" type="password" autoComplete="current-password" required className="mt-1 block w-full rounded-[3px] border border-rule bg-surface px-3 py-2" />
        </label>
        <button type="submit" className="rounded-[3px] border border-ink bg-ink px-4 py-2 text-surface">Sign in</button>
      </form>
    </div>
  );
}
