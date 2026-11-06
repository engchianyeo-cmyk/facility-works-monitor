"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

export type RequestView = {
  id: string; facilityId: string; facility: string; service: string; reason: string; raisedBy: string; raisedAt: string; status: string;
  workOrder: { id: string; label: string } | null; canRecommend: boolean;
};
type Score = { workOrder: string; capacity: string; quality: number; onTime: number; safety: number; documents: number; price: number; comments: string | null; scoredAt: string };
export type AdmissionView = {
  id: string; facilityId: string; facility: string; service: string; status: string; contractor: string; uen: string | null;
  recommendedBy: string; recommendedAt: string | null; reason: string | null;
  prequalificationNote: string | null; prequalifiedBy: string | null; ownerApprovalNote: string | null; ownerApprovalBy: string | null;
  decisionNote: string | null; decidedBy: string | null;
  trial: { jobs_scored: number; jobs_required: number; average: number | null; pass_mark: number; lowest_safety: number | null; passed: boolean } | null;
  scores: Score[];
  canPrequalify: boolean; canRecordOwnerApproval: boolean; canAdmit: boolean; canReject: boolean;
};
type Site = { id: string; name: string };
type Vendor = { id: string; name: string; trade: string | null };
type Person = { id: string; display_name: string | null; role: string };
type Manager = { id: string; profileId: string; person: string; scope: string; facilityId: string | null };

const STEPS = [
  { key: "recommended", label: "Recommended" },
  { key: "prequalified", label: "Pre-qualified" },
  { key: "on_trial", label: "Owner approved · on trial" },
  { key: "admitted", label: "Admitted to the list" },
];
const CAPACITY: Record<string, string> = { facility_manager: "Facility Manager", approver: "Approver", technician_1: "Technician 1", technician_2: "Technician 2" };
const input = "w-full rounded-lg border border-slate-300 px-3 py-2 text-sm";
const sgt = (value: string | null) => value ? new Intl.DateTimeFormat("en-SG", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Singapore" }).format(new Date(value)) : "—";

async function post(body: Record<string, unknown>) {
  const response = await fetch("/api/contractor-admission", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const result = await response.json().catch(() => ({})) as { message?: string };
  if (!response.ok) throw new Error(result.message ?? "The step could not be saved.");
}

function StepForm({ label, placeholder, action, admissionId, field, tone, onDone }: {
  label: string; placeholder: string; action: string; admissionId: string; field: "note" | "reason"; tone: "red" | "slate"; onDone: (message: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const value = String(new FormData(event.currentTarget).get(field) ?? "").trim();
    setBusy(true); setError(null);
    try { await post({ action, admission_id: admissionId, [field]: value }); setOpen(false); onDone(`${label}: saved.`); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "The step could not be saved."); }
    finally { setBusy(false); }
  }
  const button = tone === "red" ? "bg-red-600 text-white hover:bg-red-700" : "border border-slate-300 bg-white text-slate-800 hover:bg-slate-50";
  if (!open) return <button type="button" onClick={() => setOpen(true)} className={`rounded-lg px-4 py-2 text-sm font-bold ${button}`}>{label}</button>;
  return (
    <form onSubmit={submit} className="w-full space-y-2 rounded-lg border border-slate-200 bg-white p-3">
      <label className="block text-sm font-bold">{label}<textarea name={field} required minLength={5} rows={2} className={`${input} mt-1 font-normal`} placeholder={placeholder} /></label>
      {error && <p role="alert" className="text-sm font-semibold text-red-700">{error}</p>}
      <div className="flex gap-2">
        <button type="submit" disabled={busy} className={`rounded-lg px-4 py-2 text-sm font-bold disabled:opacity-50 ${button}`}>{busy ? "Saving…" : "Confirm"}</button>
        <button type="button" onClick={() => setOpen(false)} className="rounded-lg border border-slate-300 px-4 py-2 text-sm">Back</button>
      </div>
    </form>
  );
}

function RecommendForm({ sites, vendors, request, onDone, onCancel }: { sites: Site[]; vendors: Vendor[]; request: RequestView | null; onDone: (message: string) => void; onCancel: () => void }) {
  const [mode, setMode] = useState<"register" | "new">("register");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload: Record<string, unknown> = {
      facility_id: request?.facilityId ?? String(form.get("facility_id") ?? ""),
      request_id: request?.id ?? null,
      service: String(form.get("service") ?? "").trim(),
      reason: String(form.get("reason") ?? "").trim(),
    };
    if (mode === "register") payload.vendor_id = String(form.get("vendor_id") ?? "");
    else payload.new_vendor = {
      name: String(form.get("name") ?? "").trim(), company_registration_no: String(form.get("uen") ?? "").trim(),
      contact_name: String(form.get("contact_name") ?? "").trim(), contact_email: String(form.get("contact_email") ?? "").trim(),
      contact_phone: String(form.get("contact_phone") ?? "").trim(),
    };
    setBusy(true); setError(null);
    try { await post({ action: "recommend", payload }); onDone("Recommendation saved. A Procurement Manager now pre-qualifies the contractor."); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "The recommendation could not be saved."); }
    finally { setBusy(false); }
  }
  return (
    <form onSubmit={submit} className="space-y-3 rounded-xl border-2 border-red-300 bg-white p-4">
      <h3 className="text-lg font-black">Recommend a contractor{request ? ` for ${request.facility}` : ""}</h3>
      {!request && <label className="block text-sm font-bold">Facility<select name="facility_id" required className={`${input} mt-1`} defaultValue=""><option value="">Choose the facility</option>{sites.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}</select></label>}
      <label className="block text-sm font-bold">Service<input name="service" required minLength={2} defaultValue={request?.service ?? ""} className={`${input} mt-1`} placeholder="e.g. Solar PV and inverters" /></label>
      <div className="flex gap-4 text-sm">
        <label className="flex items-center gap-2"><input type="radio" checked={mode === "register"} onChange={() => setMode("register")} />From the company register</label>
        <label className="flex items-center gap-2"><input type="radio" checked={mode === "new"} onChange={() => setMode("new")} />A new company</label>
      </div>
      {mode === "register"
        ? <label className="block text-sm font-bold">Contractor<select name="vendor_id" required className={`${input} mt-1`} defaultValue=""><option value="">Choose the contractor</option>{vendors.map((vendor) => <option key={vendor.id} value={vendor.id}>{vendor.name}{vendor.trade ? ` / ${vendor.trade}` : ""}</option>)}</select></label>
        : <div className="grid gap-3 sm:grid-cols-2">
            <label className="block text-sm font-bold">Company name<input name="name" required minLength={2} className={`${input} mt-1`} /></label>
            <label className="block text-sm font-bold">UEN<input name="uen" required minLength={5} className={`${input} mt-1`} placeholder="e.g. 201834562K" /></label>
            <label className="block text-sm font-bold">Contact person<input name="contact_name" className={`${input} mt-1`} /></label>
            <label className="block text-sm font-bold">Email<input name="contact_email" type="email" className={`${input} mt-1`} /></label>
            <label className="block text-sm font-bold">Phone<input name="contact_phone" className={`${input} mt-1`} /></label>
          </div>}
      <label className="block text-sm font-bold">Why this contractor<textarea name="reason" required minLength={5} rows={2} className={`${input} mt-1`} placeholder="e.g. Proficient in inverter diagnostics; used at two other facilities." /></label>
      {error && <p role="alert" className="text-sm font-semibold text-red-700">{error}</p>}
      <div className="flex gap-2">
        <button type="submit" disabled={busy} className="rounded-lg bg-red-600 px-4 py-2 text-sm font-bold text-white hover:bg-red-700 disabled:opacity-50">{busy ? "Saving…" : "Save recommendation"}</button>
        <button type="button" onClick={onCancel} className="rounded-lg border border-slate-300 px-4 py-2 text-sm">Back</button>
      </div>
    </form>
  );
}

function Designate({ people, sites, managers, onDone }: { people: Person[]; sites: Site[]; managers: Manager[]; onDone: (message: string) => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true); setError(null);
    try { await post({ action: "designate", profile_id: String(form.get("profile_id") ?? ""), facility_id: String(form.get("facility_id") ?? "") || null, active: true }); onDone("Procurement Manager designated."); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Could not designate."); }
    finally { setBusy(false); }
  }
  async function remove(manager: Manager) {
    setBusy(true); setError(null);
    try { await post({ action: "designate", profile_id: manager.profileId, facility_id: manager.facilityId, active: false }); onDone("Procurement Manager removed."); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "Could not remove."); }
    finally { setBusy(false); }
  }
  return (
    <section className="space-y-3 rounded-xl border border-slate-200 bg-white p-5">
      <h2 className="text-xl font-black">Procurement Managers</h2>
      <p className="text-sm text-slate-600">They pre-qualify new contractors and admit them after their trial jobs. Designate for one facility, or company-wide for all facilities.</p>
      {managers.length === 0 ? <p className="text-sm font-semibold text-red-700">No Procurement Manager is designated yet, so no contractor can be pre-qualified.</p>
        : <ul className="divide-y divide-slate-100 text-sm">{managers.map((manager) => <li key={manager.id} className="flex items-center justify-between py-2"><span><b>{manager.person}</b> · {manager.scope}</span><button type="button" disabled={busy} onClick={() => void remove(manager)} className="rounded border border-slate-300 px-3 py-1 text-xs">Remove</button></li>)}</ul>}
      <form onSubmit={submit} className="grid gap-3 sm:grid-cols-[1fr_1fr_auto]">
        <select name="profile_id" required className={input} defaultValue=""><option value="">Choose the person</option>{people.map((person) => <option key={person.id} value={person.id}>{person.display_name ?? "—"} ({person.role.replace("_", " ")})</option>)}</select>
        <select name="facility_id" className={input} defaultValue=""><option value="">Company-wide (all facilities)</option>{sites.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}</select>
        <button type="submit" disabled={busy} className="rounded-lg bg-blue-700 px-4 py-2 text-sm font-bold text-white disabled:opacity-50">Designate</button>
      </form>
      {error && <p role="alert" className="text-sm font-semibold text-red-700">{error}</p>}
    </section>
  );
}

/** D-37 (6 Nov 2026): contractor admission board. */
export default function ContractorAdmissionBoard({ role, canRecommendAnywhere, recommendFacilities, vendors, requests, admissions, people, managers, sites }: {
  role: string; canRecommendAnywhere: boolean; recommendFacilities: Site[]; vendors: Vendor[]; requests: RequestView[]; admissions: AdmissionView[];
  people: Person[]; managers: Manager[]; sites: Site[];
}) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [recommending, setRecommending] = useState<RequestView | "general" | null>(null);
  const done = (text: string) => { setMessage(text); setRecommending(null); router.refresh(); };
  const open = requests.filter((request) => request.status === "open");
  const active = admissions.filter((admission) => ["recommended", "prequalified", "on_trial"].includes(admission.status));
  const decided = admissions.filter((admission) => ["admitted", "rejected"].includes(admission.status));
  const canRecommend = canRecommendAnywhere || recommendFacilities.length > 0 || ["administrator", "facility_manager"].includes(role);

  return (
    <div className="space-y-6">
      {message && <p role="status" className="rounded-lg border border-emerald-300 bg-emerald-50 p-3 text-sm font-semibold text-emerald-900">{message}</p>}

      <section className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-xl font-black">Contractor needed ({open.length})</h2>
          {canRecommend && recommending === null && <button type="button" onClick={() => setRecommending("general")} className="rounded-lg border border-slate-300 bg-white px-4 py-2 text-sm font-bold">Recommend a contractor</button>}
        </div>
        {recommending === "general" && <RecommendForm sites={recommendFacilities} vendors={vendors} request={null} onDone={done} onCancel={() => setRecommending(null)} />}
        {open.length === 0 ? <p className="text-sm text-slate-600">No open requests from Technicians.</p> : open.map((request) => (
          <article key={request.id} className={`rounded-xl border-2 bg-white p-4 ${request.canRecommend ? "border-red-500" : "border-slate-200"}`}>
            {request.canRecommend && <p className="mb-2 inline-block rounded bg-red-600 px-2 py-1 text-xs font-black uppercase text-white">Action needed — recommend a contractor</p>}
            <p className="font-black">{request.service} · {request.facility}</p>
            <p className="mt-1 text-sm text-slate-700">{request.reason}</p>
            <p className="mt-1 text-xs text-slate-500">Raised by {request.raisedBy}, {sgt(request.raisedAt)}{request.workOrder && <> · <Link href={`/work-orders/${request.workOrder.id}`} className="font-semibold text-blue-700 underline">{request.workOrder.label}</Link></>}</p>
            {request.canRecommend && (recommending !== null && recommending !== "general" && recommending.id === request.id
              ? <div className="mt-3"><RecommendForm sites={recommendFacilities} vendors={vendors} request={request} onDone={done} onCancel={() => setRecommending(null)} /></div>
              : <button type="button" onClick={() => setRecommending(request)} className="mt-3 rounded-lg bg-red-600 px-4 py-2 text-sm font-bold text-white hover:bg-red-700">Recommend a contractor</button>)}
          </article>
        ))}
      </section>

      <section className="space-y-3">
        <h2 className="text-xl font-black">In progress ({active.length})</h2>
        {active.length === 0 && <p className="text-sm text-slate-600">No contractor is being admitted.</p>}
        {active.map((admission) => {
          const yourTurn = admission.canPrequalify || admission.canRecordOwnerApproval || (admission.canAdmit && Boolean(admission.trial?.passed));
          const stepIndex = STEPS.findIndex((step) => step.key === admission.status);
          return (
            <article key={admission.id} className={`space-y-3 rounded-xl border-2 bg-white p-4 ${yourTurn ? "border-red-500" : "border-slate-200"}`}>
              {yourTurn && <p className="inline-block rounded bg-red-600 px-2 py-1 text-xs font-black uppercase text-white">Action needed — your step</p>}
              <div>
                <p className="text-lg font-black">{admission.contractor}{admission.uen ? <span className="font-normal text-slate-500"> · UEN {admission.uen}</span> : null}</p>
                <p className="text-sm text-slate-700">{admission.service} · {admission.facility}</p>
              </div>
              <ol className="flex flex-wrap gap-2 text-xs font-bold">
                {STEPS.map((step, index) => <li key={step.key} className={`rounded-full px-3 py-1 ${index < stepIndex ? "bg-emerald-100 text-emerald-900" : index === stepIndex ? "bg-blue-700 text-white" : "bg-slate-100 text-slate-500"}`}>{index + 1}. {step.label}</li>)}
              </ol>
              <dl className="grid gap-2 text-sm sm:grid-cols-3">
                <div><dt className="font-bold">Recommended by</dt><dd>{admission.recommendedBy}, {sgt(admission.recommendedAt)}</dd><dd className="text-slate-600">{admission.reason}</dd></div>
                <div><dt className="font-bold">Pre-qualification</dt><dd>{admission.prequalifiedBy ? `${admission.prequalifiedBy}: ${admission.prequalificationNote}` : "Waiting for a Procurement Manager"}</dd></div>
                <div><dt className="font-bold">Owner&apos;s approval</dt><dd>{admission.ownerApprovalBy ? `${admission.ownerApprovalBy}: ${admission.ownerApprovalNote}` : "Not yet recorded"}</dd></div>
              </dl>
              {admission.status === "on_trial" && admission.trial && (
                <div className={`rounded-lg border p-3 text-sm ${admission.trial.passed ? "border-emerald-300 bg-emerald-50" : "border-amber-300 bg-amber-50"}`}>
                  <p className="font-black">Trial: {admission.trial.jobs_scored} of {admission.trial.jobs_required} completed jobs scored · average {admission.trial.average ?? "—"} (pass mark {admission.trial.pass_mark}) · lowest safety {admission.trial.lowest_safety ?? "—"} · {admission.trial.passed ? "PASSED — ready to admit" : "not yet passed"}</p>
                  <p className="mt-1">The contractor shows as &quot;trial contractor&quot; in Prepare Proposal. Each trial job is scored on its Work Order once approved as Completed.</p>
                  {admission.scores.length > 0 && (
                    <table className="mt-2 w-full text-left text-xs"><thead><tr><th>Work Order</th><th>By</th><th>Quality</th><th>On time</th><th>Safety</th><th>Documents</th><th>Price</th><th>Comments</th></tr></thead>
                      <tbody>{admission.scores.map((score, index) => <tr key={index} className="border-t border-slate-200"><td>{score.workOrder}</td><td>{CAPACITY[score.capacity] ?? score.capacity}</td><td>{score.quality}</td><td>{score.onTime}</td><td className={score.safety === 1 ? "font-black text-red-700" : ""}>{score.safety}</td><td>{score.documents}</td><td>{score.price}</td><td>{score.comments ?? ""}</td></tr>)}</tbody></table>
                  )}
                </div>
              )}
              <div className="flex flex-wrap gap-2">
                {admission.canPrequalify && <StepForm label="Pre-qualify" placeholder="What was checked: UEN, insurance, licences…" action="prequalify" admissionId={admission.id} field="note" tone="red" onDone={done} />}
                {admission.canRecordOwnerApproval && <StepForm label="Record the owner's approval" placeholder="Who approved for the owner, when and how (e.g. director's email of 6 Nov)" action="owner_approval" admissionId={admission.id} field="note" tone="red" onDone={done} />}
                {admission.canAdmit && admission.trial?.passed && <StepForm label="Admit to the facility's list" placeholder="Note (e.g. passed both trial jobs)" action="admit" admissionId={admission.id} field="note" tone="red" onDone={done} />}
                {admission.canReject && <StepForm label="Reject" placeholder="Reason for rejecting" action="reject" admissionId={admission.id} field="reason" tone="slate" onDone={done} />}
              </div>
            </article>
          );
        })}
      </section>

      <section className="space-y-2">
        <h2 className="text-xl font-black">Decided ({decided.length})</h2>
        {decided.length === 0 ? <p className="text-sm text-slate-600">None yet.</p> : (
          <ul className="divide-y divide-slate-100 rounded-xl border border-slate-200 bg-white text-sm">
            {decided.map((admission) => <li key={admission.id} className="p-3"><b>{admission.contractor}</b> · {admission.service} · {admission.facility} — <span className={admission.status === "admitted" ? "font-bold text-emerald-700" : "font-bold text-red-700"}>{admission.status === "admitted" ? "Admitted" : "Rejected"}</span>{admission.decidedBy ? ` by ${admission.decidedBy}` : ""}{admission.decisionNote ? `: ${admission.decisionNote}` : ""}</li>)}
          </ul>
        )}
      </section>

      {role === "administrator" && <Designate people={people} sites={sites} managers={managers} onDone={done} />}
    </div>
  );
}
