"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";

/** Reads the document for SLA clauses. UAT 17 Nov 2026: the new clauses appear in section 3 at once (no manual refresh),
 * and reading the same document again does not add the same clause twice. */
export function DocumentActions({ id }: { id: string }) {
  const router = useRouter();
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <div>
      <button
        className="rounded border px-3 py-1 text-sm font-bold disabled:opacity-50"
        disabled={busy}
        onClick={async () => {
          setBusy(true);
          setMsg("Reading the document…");
          try {
            const r = await fetch(`/api/sla/documents/${id}/extract`, { method: "POST" });
            const j = (await r.json()) as { ok?: boolean; added?: number; message?: string; code?: string };
            if (!j.ok) { setMsg(j.message ?? j.code ?? "Reading failed."); return; }
            setMsg(j.message ?? `${j.added ?? 0} clause(s) found — check them in section 3, Check each clause found.`);
            router.refresh();
          } finally {
            setBusy(false);
          }
        }}
      >
        Find SLA clauses (test reader)
      </button>
      <p role="status" className="text-xs">{msg}</p>
    </div>
  );
}
