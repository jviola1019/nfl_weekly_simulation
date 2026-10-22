import { BUTTON_CLASS, Card, INPUT_CLASS, Page, PageHeader } from "@/components/ui";
import { login } from "./actions";

export const metadata = { title: "Sign in", description: "Sign in to the private desk, where paper leans and the board for the published run are kept.", robots: { index: false } };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return (
    <Page className="mx-auto max-w-md">
      <PageHeader size="compact" title="Sign in to the desk" lead="The desk is private. Public pages never show stakes." />
      <Card className="flex flex-col gap-stack">
        {error ? (
          <p role="alert" className="text-crit">That email and password did not match, or sign-in is paused after repeated attempts.</p>
        ) : null}
        <form action={login} className="flex flex-col gap-stack">
          <label className="block">
            <span className="text-sm text-ink-2">Email</span>
            <input name="email" type="email" autoComplete="username" required className={INPUT_CLASS} />
          </label>
          <label className="block">
            <span className="text-sm text-ink-2">Password</span>
            <input name="password" type="password" autoComplete="current-password" required className={INPUT_CLASS} />
          </label>
          <div>
            <button type="submit" className={BUTTON_CLASS}>Sign in</button>
          </div>
        </form>
      </Card>
    </Page>
  );
}
