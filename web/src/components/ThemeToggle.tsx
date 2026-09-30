"use client";

import { useEffect, useSyncExternalStore } from "react";

type Theme = "system" | "light" | "dark";
const KEY = "bl-theme";
const EVENT = "bl-theme-change";

function readTheme(): Theme {
  try {
    const v = window.localStorage.getItem(KEY);
    return v === "light" || v === "dark" ? v : "system";
  } catch {
    return "system"; // storage unavailable: follow the system
  }
}

function subscribe(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(EVENT, onChange);
  };
}

/** Light / night game / system. The choice is a per-viewer convenience in localStorage. */
export function ThemeToggle() {
  const theme = useSyncExternalStore(subscribe, readTheme, () => "system" as Theme);

  useEffect(() => {
    const root = document.documentElement;
    if (theme === "system") root.removeAttribute("data-theme");
    else root.setAttribute("data-theme", theme);
  }, [theme]);

  function choose(next: Theme) {
    try {
      if (next === "system") window.localStorage.removeItem(KEY);
      else window.localStorage.setItem(KEY, next);
    } catch {
      /* ignore: the page still themes for this view */
      document.documentElement.setAttribute("data-theme", next === "system" ? "" : next);
    }
    window.dispatchEvent(new Event(EVENT));
  }

  return (
    <label className="flex items-center gap-2 text-sm text-ink-2">
      <span>Theme</span>
      <select
        value={theme}
        onChange={(e) => choose(e.target.value as Theme)}
        className="rounded-[3px] border border-rule bg-surface px-2 py-1 text-ink"
      >
        <option value="system">System</option>
        <option value="light">Light</option>
        <option value="dark">Night game</option>
      </select>
    </label>
  );
}
