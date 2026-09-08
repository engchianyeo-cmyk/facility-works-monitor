"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

type Vendor = { id: string; name: string; trade: string | null; contact_name: string | null; contact_email: string | null; contact_phone: string | null; vendor_type: string; emergency_available: boolean; payment_terms_days: number };
type Category = { id: string; code: string; name: string };
type Rate = { id: string; vendor_id: string; cost_type: string; description: string; unit: string; normal_unit_rate: number; emergency_unit_rate: number | null; currency: string; effective_from: string; effective_to: string | null };

export default function ContractorManagement({ vendors, categories, rates }: { vendors: Vendor[]; categories: Category[]; rates: Rate[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>, kind: "vendor" | "rate") {
    event.preventDefault(); setBusy(true); setMessage("");
    const data = Object.fromEntries(new FormData(event.currentTarget).entries());
    try {
      const response = await fetch("/api/admin/contractors", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ kind, ...data }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.message ?? "Save failed.");
      event.currentTarget.reset(); setMessage(kind === "vendor" ? "Contractor saved." : "Unit rate saved."); router.refresh();
    } catch (error) { setMessage(error instanceof Error ? error.message : "Save failed."); }
    finally { setBusy(false); }
  }

  return <div className="space-y-8">
    {message && <div className="rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm font-semibold text-blue-900">{message}</div>}

    <section className="rounded-2xl border bg-white p-5 sm:p-6">
      <h2 className="text-xl font-black">Nominated contractors and service companies</h2>
      <p className="mt-1 text-sm text-slate-600">Register manpower providers and specialist contractors before work is assigned.</p>
      <form onSubmit={(e) => void submit(e,"vendor")} className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <label className="text-sm font-bold">Company name<input name="name" required className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <label className="text-sm font-bold">Primary trade/service<input name="trade" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <label className="text-sm font-bold">Company type<select name="vendor_type" defaultValue="specialist_contractor" className="mt-1 min-h-11 w-full rounded-lg border px-3"><option value="specialist_contractor">Specialist contractor</option><option value="manpower_provider">Manpower / staffing provider</option></select></label>
        <label className="text-sm font-bold">Contact person<input name="contact_name" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <label className="text-sm font-bold">Email<input name="contact_email" type="email" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <label className="text-sm font-bold">Phone<input name="contact_phone" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <label className="flex items-center gap-2 text-sm font-bold"><input name="emergency_available" type="checkbox" value="true" />Available for emergency dispatch</label>
        <label className="text-sm font-bold">Payment terms (days)<input name="payment_terms_days" type="number" min="1" defaultValue="30" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <div className="sm:col-span-2 lg:col-span-3"><button disabled={busy} className="min-h-11 rounded-xl bg-blue-700 px-5 font-black text-white disabled:opacity-50">Add contractor</button></div>
      </form>
      <div className="mt-6 overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr className="border-b"><th className="p-2">Company</th><th className="p-2">Type</th><th className="p-2">Trade</th><th className="p-2">Emergency</th><th className="p-2">Terms</th></tr></thead><tbody>{vendors.map(v => <tr key={v.id} className="border-b"><td className="p-2 font-bold">{v.name}</td><td className="p-2">{v.vendor_type.replaceAll("_"," ")}</td><td className="p-2">{v.trade ?? "—"}</td><td className="p-2">{v.emergency_available ? "Yes" : "No"}</td><td className="p-2">{v.payment_terms_days} days</td></tr>)}</tbody></table></div>
    </section>

    <section className="rounded-2xl border bg-white p-5 sm:p-6">
      <h2 className="text-xl font-black">Agreed unit rates</h2>
      <p className="mt-1 text-sm text-slate-600">Rates are effective-dated so historical Work Order costing is preserved.</p>
      <form onSubmit={(e) => void submit(e,"rate")} className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <label className="text-sm font-bold">Contractor<select name="vendor_id" required className="mt-1 min-h-11 w-full rounded-lg border px-3"><option value="">Select</option>{vendors.map(v => <option key={v.id} value={v.id}>{v.name}</option>)}</select></label>
        <label className="text-sm font-bold">Service category<select name="service_category_id" className="mt-1 min-h-11 w-full rounded-lg border px-3"><option value="">General</option>{categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
        <label className="text-sm font-bold">Cost type<select name="cost_type" defaultValue="labour" className="mt-1 min-h-11 w-full rounded-lg border px-3"><option value="labour">Labour</option><option value="material">Material</option><option value="equipment">Equipment</option><option value="service">Service</option><option value="callout">Call-out</option></select></label>
        <label className="text-sm font-bold">Description<input name="description" required className="mt-1 min-h-11 w-full rounded-lg border px-3" placeholder="Mechanical Technician / 13A socket / scaffold" /></label>
        <label className="text-sm font-bold">Unit<input name="unit" required className="mt-1 min-h-11 w-full rounded-lg border px-3" placeholder="hour / each / day" /></label>
        <label className="text-sm font-bold">Normal unit rate (S$)<input name="normal_unit_rate" required type="number" min="0" step="0.01" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <label className="text-sm font-bold">Emergency/OT rate (S$)<input name="emergency_unit_rate" type="number" min="0" step="0.01" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <label className="text-sm font-bold">Effective from<input name="effective_from" required type="date" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <label className="text-sm font-bold">Effective to<input name="effective_to" type="date" className="mt-1 min-h-11 w-full rounded-lg border px-3" /></label>
        <div className="sm:col-span-2 lg:col-span-4"><button disabled={busy} className="min-h-11 rounded-xl bg-emerald-700 px-5 font-black text-white disabled:opacity-50">Add agreed rate</button></div>
      </form>
      <div className="mt-6 overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr className="border-b"><th className="p-2">Contractor</th><th className="p-2">Item</th><th className="p-2">Type</th><th className="p-2">Normal rate</th><th className="p-2">Emergency/OT</th><th className="p-2">Effective</th></tr></thead><tbody>{rates.map(r => <tr key={r.id} className="border-b"><td className="p-2">{vendors.find(v=>v.id===r.vendor_id)?.name ?? "—"}</td><td className="p-2 font-bold">{r.description}</td><td className="p-2">{r.cost_type}</td><td className="p-2">S${Number(r.normal_unit_rate).toFixed(2)} / {r.unit}</td><td className="p-2">{r.emergency_unit_rate == null ? "—" : `S$${Number(r.emergency_unit_rate).toFixed(2)}`}</td><td className="p-2">{r.effective_from}{r.effective_to ? ` to ${r.effective_to}` : " onward"}</td></tr>)}</tbody></table></div>
    </section>
  </div>;
}
