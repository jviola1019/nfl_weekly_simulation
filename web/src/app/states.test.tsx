import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import ErrorPage from "./error";

describe("error state", () => {
  const error = Object.assign(new Error("password authentication failed for user ci"), { digest: "d1g3st" });
  const out = renderToStaticMarkup(<ErrorPage error={error} reset={() => {}} />);

  it("says what to do, offers a retry and quotes the digest, never the error's own message", () => {
    expect(out.match(/<h1/g)).toHaveLength(1);
    expect(out).toContain("This page could not be shown");
    expect(out).toContain('role="alert"');
    expect(out).toContain(">Try again</button>");
    expect(out).toContain("Reference d1g3st");
    expect(out).not.toContain("password authentication");
    expect(out).toContain('href="/data-health"');
  });

  it("leaves the reference out when there is no digest", () => {
    expect(renderToStaticMarkup(<ErrorPage error={new Error("x")} reset={() => {}} />)).not.toContain("Reference");
  });
});
