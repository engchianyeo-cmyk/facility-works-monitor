"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type PreviewLine = {
  line_no: number;
  item_code: string | null;
  description: string;
  worker_name: string | null;
  quantity: number;
  unit: string;
  agreed_unit_rate: number;
  actual_unit_rate: number;
  amount: number;
  rate_exception: boolean;
  exception_reason: string | null;
};

type CostResult = {
  ok?: boolean;
  code?: string;
  message?: string;
  quoted_total?: number;
  actual_total?: number;
  variance_amount?: number;
  variance_percent?: number | null;
  exception_count?: number;
  lines?: PreviewLine[];
};

type Props = {
  workOrderId: string;
  enabled: boolean;
};

function money(value: number | undefined) {
  return new Intl.NumberFormat("en-SG", { style: "currency", currency: "SGD" }).format(Number(value ?? 0));
}

function variance(value: number | undefined) {
  const amount = Number(value ?? 0);
  return `${amount > 0 ? "+" : ""}${money(amount)}`;
}

export default function ContractorActualCostPanel({ workOrderId, enabled }: Props) {
  const router = useRouter();
  const [file, setFile] = useState<File | null>(null);
  const [kind, setKind] = useState("mixed");
  const [preview, setPreview] = useState<CostResult | null>(null);
  const [busy, setBusy] = useState<"preview" | "confirm" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(mode: "preview" | "confirm") {
    if (!file || busy) return;
    setBusy(mode);
    setError(null);
    setMessage(null);
    const form = new FormData();
    form.set("file", file);
    form.set("mode", mode);
    form.set("import_kind", kind);
    try {
      const response = await fetch(`/api/work-orders/${workOrderId}/contractor-actuals`, { method: "POST", body: form });
      const body = await response.json() as CostResult & { errors?: string[] };
      if (!response.ok || body.ok !== true) {
        setError(body.errors?.join(" ") || body.message || "Contractor actual-cost import failed.");
        return;
      }
      setPreview(body);
      if (mode === "confirm") {
        setMessage("Contractor actual costs confirmed and added to the Work Order audit record.");
        setFile(null);
        router.refresh();
      }
    } catch {
      setError("The contractor actual-cost request could not be completed. Nothing was confirmed.");
    } finally {
      setBusy(null);
    }
  }

  if (!enabled) return null;

  return (
    <section aria-labelledby="contractor-actual-cost-title" className="rounded-2xl border-2 border-emerald-200 bg-white p-5 shadow-sm sm:p-6">
      <div>
        <p className="text-xs font-black uppercase tracking-wide text-emerald-700">Field commercial record</p>
        <h2 id="contractor-actual-cost-title" className="mt-1 text-xl font-black text-slate-950">Contractor actual costs</h2>
        <p className="mt-2 text-sm text-slate-600">Upload the contractor CSV, review the normalized actuals against the agreed quotation/rates, then confirm only when the figures are correct.</p>
      </div>

      <div className="mt-5 grid gap-4 sm:grid-cols-2">
        <label className="text-sm font-bold text-slate-800">CSV type
          <select value={kind} onChange={(event) => { setKind(event.target.value); setPreview(null); }} className="mt-1 min-h-11 w-full rounded-lg border border-slate-300 bg-white px-3 font-normal">
            <option value="mixed">Mixed costs</option>
            <option value="personnel">Personnel</option>
            <option value="materials">Materials</option>
            <option value="equipment_services">Equipment / services</option>
          </select>
        </label>
        <label className="text-sm font-bold text-slate-800">Contractor CSV
          <input type="file" accept=".csv,text/csv" onChange={(event) => { setFile(event.target.files?.[0] ?? null); setPreview(null); setMessage(null); }} className="mt-1 block min-h-11 w-full rounded-lg border border-slate-300 bg-white p-2 font-normal" />
        </label>
      </div>

      <button type="button" disabled={!file || busy !== null} onClick={() => void submit("preview")} className="mt-4 min-h-11 rounded-xl bg-slate-900 px-5 font-black text-white disabled:opacity-50">
        {busy === "preview" ? "Checking CSV…" : "Preview actual costs"}
      </button>

      {error && <p role="alert" className="mt-4 rounded-lg border border-red-300 bg-red-50 p-3 text-sm font-bold text-red-800">{error}</p>}
      {message && <p role="status" className="mt-4 rounded-lg border border-emerald-300 bg-emerald-50 p-3 text-sm font-bold text-emerald-900">{message}</p>}

      {preview?.ok && (
        <div className="mt-5 space-y-4">
          <dl className="grid gap-3 sm:grid-cols-4">
            <div className="rounded-xl bg-slate-50 p-3"><dt className="text-xs font-bold text-slate-500">Quotation</dt><dd className="mt-1 font-black">{money(preview.quoted_total)}</dd></div>
            <div className="rounded-xl bg-slate-50 p-3"><dt className="text-xs font-bold text-slate-500">Actual</dt><dd className="mt-1 font-black">{money(preview.actual_total)}</dd></div>
            <div className="rounded-xl bg-slate-50 p-3"><dt className="text-xs font-bold text-slate-500">Variance</dt><dd className="mt-1 font-black">{variance(preview.variance_amount)}</dd></div>
            <div className="rounded-xl bg-slate-50 p-3"><dt className="text-xs font-bold text-slate-500">Variance %</dt><dd className="mt-1 font-black">{preview.variance_percent === null || preview.variance_percent === undefined ? "—" : `${Number(preview.variance_percent) > 0 ? "+" : ""}${Number(preview.variance_percent).toFixed(2)}%`}</dd></div>
          </dl>
          <p className="text-sm font-bold text-slate-700">Rate exceptions requiring explanation: {preview.exception_count ?? 0}</p>
          <div className="overflow-x-auto rounded-xl border border-slate-200">
            <table className="min-w-full text-left text-sm">
              <thead className="bg-slate-100 text-xs uppercase text-slate-600"><tr><th className="p-3">Item / person</th><th className="p-3">Qty</th><th className="p-3">Agreed</th><th className="p-3">Actual</th><th className="p-3">Amount</th><th className="p-3">Exception</th></tr></thead>
              <tbody>{(preview.lines ?? []).map((line) => <tr key={line.line_no} className="border-t border-slate-200"><td className="p-3"><span className="font-bold">{line.item_code || line.description}</span>{line.worker_name ? <span className="block text-slate-500">{line.worker_name}</span> : null}</td><td className="p-3">{line.quantity} {line.unit}</td><td className="p-3">{money(line.agreed_unit_rate)}</td><td className="p-3">{money(line.actual_unit_rate)}</td><td className="p-3 font-bold">{money(line.amount)}</td><td className="p-3">{line.rate_exception ? line.exception_reason || "Rate differs" : "—"}</td></tr>)}</tbody>
            </table>
          </div>
          <button type="button" disabled={!file || busy !== null} onClick={() => void submit("confirm")} className="min-h-12 rounded-xl bg-emerald-700 px-5 font-black text-white disabled:opacity-50">
            {busy === "confirm" ? "Confirming…" : "Confirm contractor actual costs"}
          </button>
        </div>
      )}
    </section>
  );
}
