"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { FACILITY_COOKIE } from "@/lib/facility-scope";

/**
 * D-82 (22 Nov 2026): a row of buttons to choose the facility a page shows — "All facilities", then each facility.
 * The choice is remembered in this browser and carried to every page. Optional counts (e.g. unread notices) show on
 * each button. With one facility only, the facility's name is shown instead of buttons.
 */
export default function FacilityButtons({ facilities, current, allowAll = true, counts, countLabel }: {
  facilities: Array<{ id: string; name: string }>;
  current: string;
  allowAll?: boolean;
  counts?: Record<string, number>;
  countLabel?: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  if (facilities.length === 0) return null;
  if (facilities.length === 1) return <p className="text-sm text-slate-600">Facility: <span className="font-semibold text-slate-900">{facilities[0].name}</span></p>;
  function choose(id: string) {
    document.cookie = `${FACILITY_COOKIE}=${encodeURIComponent(id)}; path=/; max-age=31536000; samesite=lax`;
    const next = new URLSearchParams(params?.toString() ?? "");
    next.delete("facility");
    const query = next.toString();
    router.replace(query ? `${pathname}?${query}` : pathname);
    router.refresh();
  }
  const total = counts ? Object.values(counts).reduce((sum, n) => sum + n, 0) : 0;
  const options = [...(allowAll ? [{ id: "all", name: "All facilities" }] : []), ...facilities];
  return (
    <nav aria-label="Choose the facility shown" className="flex flex-wrap gap-2">
      {options.map((option) => {
        const n = option.id === "all" ? total : counts?.[option.id] ?? 0;
        const active = option.id === current;
        return (
          <button key={option.id} type="button" aria-pressed={active} onClick={() => choose(option.id)}
            className={`min-h-11 rounded-full border px-4 text-sm font-bold ${active ? "border-slate-900 bg-slate-900 text-white" : "border-slate-300 bg-white text-slate-800 hover:bg-slate-50"}`}>
            {option.name}
            {counts && n > 0 && <span className={`ml-2 rounded-full px-2 py-0.5 text-xs font-black ${active ? "bg-white text-red-700" : "bg-red-600 text-white"}`} aria-label={`${n} ${countLabel ?? "new"}`}>{n}</span>}
          </button>
        );
      })}
    </nav>
  );
}
