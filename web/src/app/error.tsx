"use client";

import Link from "next/link";
import { useEffect } from "react";
import { BUTTON_CLASS, Card, Page, PageHeader } from "@/components/ui";

/**
 * The last resort for a page that threw while it rendered: what happened, what to do, and a
 * reference to quote. It never prints the error's own message or stack (those can carry
 * internals); the error is logged to the console and, with the same digest, to the server log.
 */
export default function ErrorPage({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <Page className="max-w-xl">
      <PageHeader size="compact" title="This page could not be shown" lead="Something went wrong while it loaded. No data was changed." />
      <Card role="alert" className="flex flex-col gap-control">
        <p className="text-sm text-ink-2">
          Try again. If it keeps happening, the data behind the page may be unavailable: <Link href="/data-health">Data health</Link> says
          what the last run reached.
        </p>
        {error.digest ? <p className="num text-sm text-muted">Reference {error.digest}</p> : null}
        <div>
          <button type="button" onClick={reset} className={BUTTON_CLASS}>
            Try again
          </button>
        </div>
      </Card>
    </Page>
  );
}
