import Link from "next/link";
import { Page, PageHeader } from "@/components/ui";

export default function NotFound() {
  return (
    <Page className="max-w-xl">
      <PageHeader size="compact" title="Not found" lead={<>That page or game is not in the published data. <Link href="/">Back to this week</Link></>} />
    </Page>
  );
}
