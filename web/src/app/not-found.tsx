import Link from "next/link";
import { PageTitle } from "@/components/ui";

export default function NotFound() {
  return (
    <div className="max-w-xl">
      <PageTitle compact lead={<>That page or game is not in the published data. <Link href="/">Back to this week</Link></>}>
        Not found
      </PageTitle>
    </div>
  );
}
