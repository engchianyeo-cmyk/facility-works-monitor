"use client";

import { usePathname } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";

/** UAT 16 Nov 2026 (owner): on phones the header links fold under a Menu button; on larger screens they show as before. */
export default function CollapsibleNav({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  useEffect(() => setOpen(false), [pathname]);
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        aria-expanded={open}
        aria-controls="main-navigation"
        className="flex min-h-11 items-center justify-center gap-2 rounded-lg border border-slate-300 bg-white px-4 text-sm font-semibold text-slate-800 md:hidden"
      >
        <span aria-hidden="true">{open ? "✕" : "☰"}</span> {open ? "Close menu" : "Menu"}
      </button>
      <div id="main-navigation" className={`${open ? "block" : "hidden"} md:block`}>{children}</div>
    </>
  );
}
