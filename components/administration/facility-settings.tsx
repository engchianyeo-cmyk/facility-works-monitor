"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { roleLabel } from "@/lib/product-terminology";
import { ENDORSEMENT_STAGES, type EndorsementStage } from "@/lib/facility-settings";

type Candidate = { id: string; display_name: string; role: string };

/** D-11: Administrator form for one facility — designated Approver and when the second Technician endorses. */
export default function FacilitySettingsForm({ facilityId, facilityName, approverId, stage, candidates }: {
  facilityId: string; facilityName: string; approverId: string | null; stage: EndorsementStage; candidates: Candidate[];
}) {
  const router = useRouter();
  const [approver, setApprover] = useState(approverId ?? "");
  const [chosenStage, setChosenStage] = useState<EndorsementStage>(stage);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setMessage("");
    try {
      const response = await fetch("/api/administration/facility-settings", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ facility_id: facilityId, designated_approver_id: approver || null, endorsement_stage: chosenStage, reason }),
      });
      const result = await response.json();
      setFailed(!response.ok);
      setMessage(response.ok ? "Facility settings saved." : result.message ?? "Facility settings could not be saved.");
      if (response.ok) { setReason(""); router.refresh(); }
    } catch { setFailed(true); setMessage("Facility settings could not be saved. Try again."); }
    finally { setBusy(false); }
  }

  return <form onSubmit={save} className="space-y-5" aria-label={`Settings for ${facilityName}`}>
    <label className="block font-semibold">Designated Approver
      <select value={approver} onChange={(event) => setApprover(event.target.value)} className="mt-2 block min-h-11 w-full rounded border bg-white p-2 font-normal">
        <option value="">Not designated — any Approver, Supervisor or Facility Manager of this facility</option>
        {candidates.map((person) => <option key={person.id} value={person.id}>{person.display_name} · {roleLabel(person.role)}</option>)}
      </select>
      <span className="mt-1 block text-sm font-normal text-slate-600">The designated Approver is notified first. The facility&apos;s Supervisor and Facility Manager may still approve within their limits.</span>
    </label>
    <fieldset>
      <legend className="font-semibold">When the second Technician endorses the Work Order</legend>
      <div className="mt-2 space-y-2">
        {ENDORSEMENT_STAGES.map((option) => (
          <label key={option.value} className={`flex min-h-11 cursor-pointer gap-3 rounded-lg border p-3 ${chosenStage === option.value ? "border-blue-500 bg-blue-50" : "border-slate-200"}`}>
            <input type="radio" name={`stage-${facilityId}`} value={option.value} checked={chosenStage === option.value} onChange={() => setChosenStage(option.value)} className="mt-1" />
            <span><span className="block font-semibold">{option.label}</span><span className="block text-sm text-slate-600">{option.help}</span></span>
          </label>
        ))}
      </div>
    </fieldset>
    <label className="block font-semibold">Reason for change
      <textarea required minLength={3} maxLength={1000} value={reason} onChange={(event) => setReason(event.target.value)} className="mt-2 block w-full rounded border p-2 font-normal" />
    </label>
    <button disabled={busy} className="min-h-11 rounded bg-blue-700 px-5 font-bold text-white disabled:opacity-50">{busy ? "Saving…" : "Save facility settings"}</button>
    {message && <p role={failed ? "alert" : "status"} className={failed ? "text-red-700" : "text-emerald-700"}>{message}</p>}
  </form>;
}
