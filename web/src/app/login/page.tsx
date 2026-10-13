import { BUTTON_CLASS, Card, INPUT_CLASS, PageTitle } from "@/components/ui";
import { login } from "./actions";

export const metadata = { title: "Sign in", robots: { index: false } };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return (
    <div className="mx-auto max-w-md">
      <PageTitle compact lead="The desk is private. Public pages never show stakes.">
        Sign in to the desk
      </PageTitle>
      <Card className="mt-6">
        {error ? (
          <p role="alert" className="mb-4 text-crit">That email and password did not match, or sign-in is paused after repeated attempts.</p>
        ) : null}
        <form action={login} className="space-y-4">
          <label className="block">
            <span className="text-sm text-ink-2">Email</span>
            <input name="email" type="email" autoComplete="username" required className={INPUT_CLASS} />
          </label>
          <label className="block">
            <span className="text-sm text-ink-2">Password</span>
            <input name="password" type="password" autoComplete="current-password" required className={INPUT_CLASS} />
          </label>
          <button type="submit" className={BUTTON_CLASS}>Sign in</button>
        </form>
      </Card>
    </div>
  );
}
