"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { roleLabel } from "@/lib/product-terminology";
import { facilityDrawingSrc, MAX_DRAWING_BYTES, type FacilityDrawingRow } from "@/lib/facility-drawings";

/** D-17: Administrator screens for facility setup — new facility, details, areas, drawings and staff. */

type Outcome = { ok: boolean; message: string };

async function send(url: string, method: string, body: unknown): Promise<Outcome & { data?: Record<string, unknown> }> {
  try {
    const response = await fetch(url, body instanceof FormData ? { method, body } : { method, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const data = await response.json().catch(() => ({}));
    return { ok: response.ok, message: String(data.message ?? (response.ok ? "Saved." : "Could not be saved. Try again.")), data };
  } catch { return { ok: false, message: "Could not be saved. Check your connection and try again." }; }
}

function Result({ outcome }: { outcome: Outcome | null }) {
  if (!outcome) return null;
  return <p role={outcome.ok ? "status" : "alert"} className={`text-sm ${outcome.ok ? "text-emerald-700" : "text-red-700"}`}>{outcome.message}</p>;
}

const input = "mt-1 block min-h-11 w-full rounded border bg-white p-2 font-normal";
const button = "min-h-11 rounded bg-blue-700 px-5 font-bold text-white disabled:opacity-50";

function useSubmit() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  async function run(task: () => Promise<Outcome>, after?: () => void) {
    setBusy(true); setOutcome(null);
    const result = await task();
    setOutcome(result); setBusy(false);
    if (result.ok) { after?.(); router.refresh(); }
  }
  return { busy, outcome, run };
}

export function AddFacilityForm() {
  const { busy, outcome, run } = useSubmit();
  const [code, setCode] = useState(""); const [name, setName] = useState(""); const [address, setAddress] = useState("");
  const [seed, setSeed] = useState(true); const [reason, setReason] = useState("New facility");
  return <form className="grid gap-3 sm:grid-cols-2" aria-label="Add a new facility" onSubmit={(event) => {
    event.preventDefault();
    void run(async () => {
      const result = await send("/api/administration/facilities", "POST", { facility_id: null, code, name, address, seed_standard_areas: seed, reason });
      const added = Number(result.data?.standard_areas_added ?? 0);
      return result.ok ? { ok: true, message: `Facility added${added ? ` with ${added} standard areas` : ""}. Add its drawings and staff below.` } : result;
    }, () => { setCode(""); setName(""); setAddress(""); });
  }}>
    <label className="font-semibold">Facility code<input required pattern="[A-Za-z0-9][A-Za-z0-9-]{1,19}" maxLength={20} value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="e.g. TPY-01" className={input} /></label>
    <label className="font-semibold">Facility name<input required minLength={2} maxLength={120} value={name} onChange={(e) => setName(e.target.value)} className={input} /></label>
    <label className="font-semibold sm:col-span-2">Address<input maxLength={500} value={address} onChange={(e) => setAddress(e.target.value)} placeholder="Street, building, postal code" className={input} /></label>
    <label className="flex min-h-11 items-center gap-2 sm:col-span-2"><input type="checkbox" checked={seed} onChange={(e) => setSeed(e.target.checked)} /> Start with the standard area list (Reception, Office, Plant rooms, Generator Room…). You can add more areas later.</label>
    <label className="font-semibold sm:col-span-2">Reason<input required minLength={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} className={input} /></label>
    <div className="space-y-2 sm:col-span-2"><button disabled={busy} className={button}>{busy ? "Adding…" : "Add facility"}</button><Result outcome={outcome} /></div>
    <p className="text-sm text-slate-600 sm:col-span-2">A new facility starts on the recommended settings (endorsement before the Approver&apos;s review). Change them in its Settings section.</p>
  </form>;
}

export function FacilityDetailsForm({ facility }: { facility: { id: string; code: string; name: string; address: string | null; is_active: boolean } }) {
  const { busy, outcome, run } = useSubmit();
  const [code, setCode] = useState(facility.code); const [name, setName] = useState(facility.name);
  const [address, setAddress] = useState(facility.address ?? ""); const [active, setActive] = useState(facility.is_active); const [reason, setReason] = useState("");
  return <form className="grid gap-3 sm:grid-cols-2" aria-label={`Details for ${facility.name}`} onSubmit={(event) => {
    event.preventDefault();
    void run(() => send("/api/administration/facilities", "POST", { facility_id: facility.id, code, name, address, active, reason }).then((r) => r.ok ? { ok: true, message: "Facility details saved." } : r), () => setReason(""));
  }}>
    <label className="font-semibold">Facility code<input required maxLength={20} value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} className={input} /></label>
    <label className="font-semibold">Facility name<input required maxLength={120} value={name} onChange={(e) => setName(e.target.value)} className={input} /></label>
    <label className="font-semibold sm:col-span-2">Address<input maxLength={500} value={address} onChange={(e) => setAddress(e.target.value)} className={input} /></label>
    <label className="flex min-h-11 items-center gap-2 sm:col-span-2"><input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} /> Facility is in use (switching off is refused while it has open Work Orders)</label>
    <label className="font-semibold sm:col-span-2">Reason for change<input required minLength={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} className={input} /></label>
    <div className="space-y-2 sm:col-span-2"><button disabled={busy} className={button}>{busy ? "Saving…" : "Save details"}</button><Result outcome={outcome} /></div>
  </form>;
}

export function AddAreaForm({ facilityId }: { facilityId: string }) {
  const { busy, outcome, run } = useSubmit();
  const [code, setCode] = useState(""); const [name, setName] = useState(""); const [level, setLevel] = useState("");
  return <form className="grid gap-3 sm:grid-cols-[1fr_2fr_1fr_auto] sm:items-end" aria-label="Add an area" onSubmit={(event) => {
    event.preventDefault();
    void run(() => send(`/api/administration/facilities/${facilityId}/areas`, "POST", { area_code: code, name, level }).then((r) => r.ok ? { ok: true, message: "Area added." } : r), () => { setCode(""); setName(""); setLevel(""); });
  }}>
    <label className="text-sm font-semibold">Area code<input required maxLength={20} value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="ELR-02" className={input} /></label>
    <label className="text-sm font-semibold">Area name<input required maxLength={120} value={name} onChange={(e) => setName(e.target.value)} placeholder="Electrical Riser Level 2" className={input} /></label>
    <label className="text-sm font-semibold">Level<input maxLength={40} value={level} onChange={(e) => setLevel(e.target.value)} placeholder="L2" className={input} /></label>
    <button disabled={busy} className={button}>{busy ? "Adding…" : "Add area"}</button>
    <div className="sm:col-span-4"><Result outcome={outcome} /></div>
  </form>;
}

function imageSize(file: File): Promise<{ width: number; height: number } | null> {
  if (file.type === "application/pdf") return Promise.resolve(null);
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file); const img = new window.Image();
    img.onload = () => { resolve({ width: img.naturalWidth, height: img.naturalHeight }); URL.revokeObjectURL(url); };
    img.onerror = () => { resolve({ width: 0, height: 0 }); URL.revokeObjectURL(url); };
    img.src = url;
  });
}

export function DrawingUploadForm({ facilityId }: { facilityId: string }) {
  const { busy, outcome, run } = useSubmit();
  const [file, setFile] = useState<File | null>(null); const [code, setCode] = useState(""); const [title, setTitle] = useState(""); const [revision, setRevision] = useState("");
  const [formKey, setFormKey] = useState(0);
  return <form key={formKey} className="grid gap-3 sm:grid-cols-2" aria-label="Upload a drawing" onSubmit={(event) => {
    event.preventDefault();
    if (!file) return;
    void run(async () => {
      if (file.size > MAX_DRAWING_BYTES) return { ok: false, message: "Drawings must be smaller than 50 MB." };
      const size = await imageSize(file);
      const form = new FormData();
      form.set("file", file); form.set("code", code); form.set("title", title); form.set("revision", revision);
      if (size) { form.set("width", String(size.width)); form.set("height", String(size.height)); }
      const result = await send(`/api/administration/facilities/${facilityId}/drawings`, "POST", form);
      return result.ok ? { ok: true, message: "Drawing uploaded. Staff of this facility can now view and download it." } : result;
    }, () => { setFile(null); setCode(""); setTitle(""); setRevision(""); setFormKey((k) => k + 1); });
  }}>
    <label className="font-semibold sm:col-span-2">Drawing file (PNG, JPEG, WebP or PDF, up to 50 MB)
      <input required type="file" accept="image/png,image/jpeg,image/webp,application/pdf" onChange={(e) => setFile(e.target.files?.[0] ?? null)} className={input} />
    </label>
    <label className="font-semibold">Drawing number<input required pattern="[A-Za-z0-9][A-Za-z0-9-]{0,23}" maxLength={24} value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="e.g. TPY-L1-001" className={input} /></label>
    <label className="font-semibold">Revision<input maxLength={40} value={revision} onChange={(e) => setRevision(e.target.value)} placeholder="e.g. Rev A" className={input} /></label>
    <label className="font-semibold sm:col-span-2">Title<input required maxLength={160} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Level 1 floor plan" className={input} /></label>
    <div className="space-y-2 sm:col-span-2"><button disabled={busy || !file} className={button}>{busy ? "Uploading…" : "Upload drawing"}</button><Result outcome={outcome} /></div>
    <p className="text-sm text-slate-600 sm:col-span-2">Image drawings can also be used to pin areas and mark up Work Orders. PDF drawings are for viewing and download.</p>
  </form>;
}

export function DrawingList({ drawings, canRemove }: { drawings: FacilityDrawingRow[]; canRemove: boolean }) {
  const { busy, outcome, run } = useSubmit();
  const [removing, setRemoving] = useState<string | null>(null); const [reason, setReason] = useState("");
  if (drawings.length === 0) return <p className="text-sm text-slate-600">No drawings uploaded yet. Work Orders at this facility use the mock-up drawings until you upload one.</p>;
  return <div className="space-y-2">
    <ul className="divide-y rounded-lg border">
      {drawings.map((drawing) => <li key={drawing.id} className="flex flex-wrap items-center gap-3 p-3">
        <span className="min-w-0 flex-1"><span className="block font-semibold">{drawing.code} — {drawing.title}</span>
          <span className="block text-sm text-slate-600">{drawing.revision ?? "No revision"} · {drawing.content_type === "application/pdf" ? "PDF" : "Image"} · {(drawing.byte_size / 1024 / 1024).toFixed(1)} MB · {drawing.original_filename}</span></span>
        <a href={facilityDrawingSrc(drawing.id)} target="_blank" rel="noopener" className="min-h-11 rounded border px-3 py-2 text-sm font-semibold text-blue-700">View</a>
        <a href={facilityDrawingSrc(drawing.id, true)} className="min-h-11 rounded border px-3 py-2 text-sm font-semibold text-blue-700">Download</a>
        {canRemove && <button type="button" onClick={() => { setRemoving(drawing.id); setReason(""); }} className="min-h-11 rounded border border-red-200 px-3 py-2 text-sm font-semibold text-red-700">Remove</button>}
        {removing === drawing.id && <form className="flex w-full flex-wrap items-end gap-2" onSubmit={(event) => {
          event.preventDefault();
          void run(() => send(`/api/administration/facility-drawings/${drawing.id}`, "DELETE", { reason }).then((r) => r.ok ? { ok: true, message: `${drawing.code} removed.` } : r), () => setRemoving(null));
        }}>
          <label className="flex-1 text-sm font-semibold">Reason for removing {drawing.code}<input required minLength={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Superseded by Rev B" className={input} /></label>
          <button disabled={busy} className="min-h-11 rounded bg-red-700 px-4 font-bold text-white disabled:opacity-50">Confirm remove</button>
          <button type="button" onClick={() => setRemoving(null)} className="min-h-11 rounded border px-4">Cancel</button>
        </form>}
      </li>)}
    </ul>
    <Result outcome={outcome} />
  </div>;
}

type StaffRow = { profile_id: string; display_name: string; email: string | null; role: string; member: boolean; member_since: string | null };

export function FacilityStaff({ facilityId, staff }: { facilityId: string; staff: StaffRow[] }) {
  const { busy, outcome, run } = useSubmit();
  const [chosen, setChosen] = useState(""); const [reason, setReason] = useState("");
  const [removing, setRemoving] = useState<string | null>(null); const [removeReason, setRemoveReason] = useState("");
  const members = staff.filter((row) => row.member); const others = staff.filter((row) => !row.member);
  function change(profileId: string, active: boolean, why: string) {
    void run(() => send(`/api/administration/facilities/${facilityId}/staff`, "POST", { profile_id: profileId, active, reason: why })
      .then((r) => r.ok ? { ok: true, message: r.data?.code === "NO_CHANGE" ? "No change was needed." : active ? "Staff member added to this facility." : "Staff member removed from this facility." } : r),
      () => { setChosen(""); setReason(""); setRemoving(null); });
  }
  return <div className="space-y-3">
    {members.length === 0 ? <p className="text-sm text-slate-600">No staff assigned yet.</p> : <ul className="divide-y rounded-lg border">
      {members.map((row) => <li key={row.profile_id} className="flex flex-wrap items-center gap-3 p-3">
        <span className="min-w-0 flex-1"><span className="block font-semibold">{row.display_name} · {roleLabel(row.role)}</span>
          <span className="block text-sm text-slate-600">{row.email ?? "No email"}{row.member_since ? ` · since ${new Date(row.member_since).toLocaleDateString("en-SG", { timeZone: "Asia/Singapore" })}` : ""}</span></span>
        <button type="button" disabled={busy} onClick={() => { setRemoving(row.profile_id); setRemoveReason(""); }}
          className="min-h-11 rounded border border-red-200 px-3 py-2 text-sm font-semibold text-red-700 disabled:opacity-50">Remove</button>
        {removing === row.profile_id && <form className="flex w-full flex-wrap items-end gap-2" onSubmit={(event) => { event.preventDefault(); change(row.profile_id, false, removeReason); }}>
          <label className="flex-1 text-sm font-semibold">Reason for removing {row.display_name}<input required minLength={3} maxLength={1000} value={removeReason} onChange={(e) => setRemoveReason(e.target.value)} placeholder="e.g. Transferred to another site" className={input} /></label>
          <button disabled={busy} className="min-h-11 rounded bg-red-700 px-4 font-bold text-white disabled:opacity-50">Confirm remove</button>
          <button type="button" onClick={() => setRemoving(null)} className="min-h-11 rounded border px-4">Cancel</button>
        </form>}
      </li>)}
    </ul>}
    <form className="grid gap-3 sm:grid-cols-[2fr_2fr_auto] sm:items-end" aria-label="Add a staff member" onSubmit={(event) => { event.preventDefault(); if (chosen) change(chosen, true, reason); }}>
      <label className="text-sm font-semibold">Add staff member
        <select required value={chosen} onChange={(e) => setChosen(e.target.value)} className={input}>
          <option value="">Choose…</option>
          {others.map((row) => <option key={row.profile_id} value={row.profile_id}>{row.display_name} · {roleLabel(row.role)}</option>)}
        </select>
      </label>
      <label className="text-sm font-semibold">Reason<input required minLength={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Assigned to this site" className={input} /></label>
      <button disabled={busy || !chosen} className={button}>Add</button>
    </form>
    <Result outcome={outcome} />
    <p className="text-sm text-slate-600">Only Technicians, Approvers, Supervisors and Facility Managers belong to a facility. New user accounts are created in <a href="/administration/users" className="font-semibold text-blue-700 underline">Users</a>.</p>
  </div>;
}
