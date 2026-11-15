"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { FACILITY_COOKIE } from "@/lib/facility-scope";

/** D-50 / D-54: choose which facility the lists show; remembered in this browser. */

export default function FacilitySwitch({ facilities, current, allowAll }: {
  facilities: Array<{ id: string; name: string }>;
  current: string;
  allowAll: boolean;
}) {
  const router = useRouter();
  const [value, setValue] = useState(current);
  return (
    <label className="flex items-center gap-2 rounded-lg border border-slate-300 bg-white px-2 py-1 text-sm font-semibold text-slate-700">
      <span className="sr-only sm:not-sr-only">Facility</span>
      <select
        aria-label="Facility shown"
        value={value}
        onChange={(event) => {
          const next = event.target.value;
          setValue(next);
          document.cookie = `${FACILITY_COOKIE}=${encodeURIComponent(next)}; path=/; max-age=31536000; samesite=lax`;
          router.refresh();
        }}
        className="rounded-md bg-transparent px-1 py-1 text-sm"
      >
        {allowAll && <option value="all">All facilities</option>}
        {facilities.map((facility) => <option key={facility.id} value={facility.id}>{facility.name}</option>)}
      </select>
    </label>
  );
}
