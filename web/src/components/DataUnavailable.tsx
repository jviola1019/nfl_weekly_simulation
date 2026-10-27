import { Card } from "@/components/ui";

/** An honest empty state: what is missing, why, and what would fill it. */
export function DataUnavailable({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Card tone="sunken" pad="sm" className="flex flex-col gap-tight">
      <p className="font-medium">{title}</p>
      <div className="text-sm text-ink-2">{children}</div>
    </Card>
  );
}
