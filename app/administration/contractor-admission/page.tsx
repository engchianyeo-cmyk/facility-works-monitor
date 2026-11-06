import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import ContractorAdmissionBoard, { type AdmissionView, type RequestView } from "@/components/administration/contractor-admission-board";

export const revalidate = 0;

// D-37 (6 Nov 2026): Contractor needed requests, recommendation, pre-qualification, owner's approval, trial and admission.
export default async function ContractorAdmissionPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/contractor-admission");
  const supabase = await createClient();
  const { data: myDesignations } = await supabase.from("procurement_managers").select("facility_id").eq("profile_id", identity.userId).eq("active", true);
  const procurementScopes = (myDesignations ?? []).map((row) => (row as { facility_id: string | null }).facility_id);
  const management = ["administrator", "facility_manager", "supervisor"].includes(identity.role);
  if (!management && procurementScopes.length === 0) {
    return <main className="mx-auto max-w-xl p-8"><div className="rounded-xl border border-red-200 bg-red-50 p-6"><h1 className="text-2xl font-bold text-red-900">Access denied</h1><p className="mt-2 text-red-800">Contractor admission is for Facility Managers, Administrators and Procurement Managers.</p></div></main>;
  }

  const [sites, requests, admissions, vendors, evaluations, people, managers] = await Promise.all([
    supabase.from("sites").select("id,code,name").eq("is_active", true).order("name"),
    supabase.from("contractor_requests").select("id,facility_id,work_order_id,service,reason,raised_by,raised_at,status").order("raised_at", { ascending: false }).limit(100),
    supabase.from("contractor_admissions").select("*").order("recommended_at", { ascending: false }).limit(200),
    supabase.from("vendors").select("id,name,trade,company_registration_no").eq("active", true).is("deleted_at", null).order("name"),
    supabase.from("contractor_trial_evaluations").select("admission_id,work_order_id,scorer_capacity,quality,on_time,safety,documents,price,comments,scored_at"),
    supabase.from("profiles").select("id,display_name,role").eq("is_active", true).is("deleted_at", null).order("display_name"),
    supabase.from("procurement_managers").select("id,profile_id,facility_id,active,designated_at").eq("active", true),
  ]);
  const unavailable = sites.error || requests.error || admissions.error || vendors.error;
  const workOrderIds = Array.from(new Set((requests.data ?? []).map((row) => (row as { work_order_id: string | null }).work_order_id).filter(Boolean))) as string[];
  const evaluatedIds = Array.from(new Set((evaluations.data ?? []).map((row) => (row as { work_order_id: string }).work_order_id)));
  const { data: orders } = workOrderIds.length + evaluatedIds.length
    ? await supabase.from("work_orders").select("id,work_order_number,title").in("id", [...workOrderIds, ...evaluatedIds])
    : { data: [] };
  const trialIds = (admissions.data ?? []).filter((row) => (row as { status: string }).status === "on_trial").map((row) => (row as { id: string }).id);
  const trialResults = Object.fromEntries(await Promise.all(trialIds.map(async (id) => {
    const { data } = await supabase.rpc("contractor_trial_result", { p_admission_id: id });
    return [id, data] as const;
  })));

  const nameOf = new Map((people.data ?? []).map((row) => [(row as { id: string }).id, (row as { display_name: string | null }).display_name ?? "Unknown"]));
  const siteName = new Map((sites.data ?? []).map((row) => [(row as { id: string }).id, (row as { name: string }).name]));
  const vendorOf = new Map((vendors.data ?? []).map((row) => [(row as { id: string }).id, row as { id: string; name: string; trade: string | null; company_registration_no: string | null }]));
  const orderOf = new Map((orders ?? []).map((row) => [(row as { id: string }).id, row as { id: string; work_order_number: string | null; title: string }]));
  const isPm = (facility: string) => procurementScopes.some((scope) => scope === null || scope === facility);
  const isFm = (facility: string) => identity.role === "facility_manager" && Boolean(facility);

  const requestViews: RequestView[] = (requests.data ?? []).map((raw) => {
    const row = raw as { id: string; facility_id: string; work_order_id: string | null; service: string; reason: string; raised_by: string; raised_at: string; status: string };
    const order = row.work_order_id ? orderOf.get(row.work_order_id) : undefined;
    return { id: row.id, facilityId: row.facility_id, facility: siteName.get(row.facility_id) ?? "Facility", service: row.service, reason: row.reason,
      raisedBy: nameOf.get(row.raised_by) ?? "Technician", raisedAt: row.raised_at, status: row.status,
      workOrder: order ? { id: order.id, label: `${order.work_order_number ?? ""} ${order.title}`.trim() } : null,
      canRecommend: row.status === "open" && (identity.role === "administrator" || isFm(row.facility_id) || isPm(row.facility_id)) };
  });

  const admissionViews: AdmissionView[] = (admissions.data ?? []).map((raw) => {
    const row = raw as Record<string, string | null> & { id: string; facility_id: string; vendor_id: string; status: string; service: string };
    const vendor = vendorOf.get(row.vendor_id);
    const scores = (evaluations.data ?? []).filter((e) => (e as { admission_id: string }).admission_id === row.id).map((e) => {
      const ev = e as { work_order_id: string; scorer_capacity: string; quality: number; on_time: number; safety: number; documents: number; price: number; comments: string | null; scored_at: string };
      const order = orderOf.get(ev.work_order_id);
      return { workOrder: order ? `${order.work_order_number ?? ""} ${order.title}`.trim() : "Work Order", capacity: ev.scorer_capacity,
        quality: ev.quality, onTime: ev.on_time, safety: ev.safety, documents: ev.documents, price: ev.price, comments: ev.comments, scoredAt: ev.scored_at };
    });
    return {
      id: row.id, facilityId: row.facility_id, facility: siteName.get(row.facility_id) ?? "Facility", service: row.service, status: row.status,
      contractor: vendor?.name ?? "Contractor", uen: vendor?.company_registration_no ?? null,
      recommendedBy: nameOf.get(row.recommended_by ?? "") ?? "—", recommendedAt: row.recommended_at, reason: row.recommendation_reason,
      prequalificationNote: row.prequalification_note, prequalifiedBy: row.prequalified_by ? nameOf.get(row.prequalified_by) ?? "—" : null,
      ownerApprovalNote: row.owner_approval_note, ownerApprovalBy: row.owner_approval_recorded_by ? nameOf.get(row.owner_approval_recorded_by) ?? "—" : null,
      decisionNote: row.decision_note, decidedBy: row.decided_by ? nameOf.get(row.decided_by) ?? "—" : null,
      trial: (trialResults[row.id] ?? null) as AdmissionView["trial"], scores,
      canPrequalify: row.status === "recommended" && isPm(row.facility_id),
      canRecordOwnerApproval: row.status === "prequalified" && (isFm(row.facility_id) || isPm(row.facility_id)),
      canAdmit: row.status === "on_trial" && isPm(row.facility_id),
      canReject: ["recommended", "prequalified", "on_trial"].includes(row.status) && (isFm(row.facility_id) || isPm(row.facility_id)),
    };
  });

  return (
    <main className="mx-auto max-w-7xl space-y-6 p-4 sm:p-8">
      <header>
        <p className="text-sm font-black uppercase tracking-widest text-blue-700">Administration</p>
        <h1 className="text-3xl font-black">Contractor Admission</h1>
        <p className="mt-2 max-w-3xl text-slate-600">
          How a new contractor joins a facility&apos;s list: recommendation, pre-qualification by a Procurement Manager, the facility owner&apos;s approval,
          trial jobs scored after completion, then admission. Steps waiting for you are outlined in red. See also <Link href="/administration/contractors" className="font-semibold text-blue-700 underline">Contractors &amp; Agreed Rates</Link>.
        </p>
      </header>
      {unavailable
        ? <div className="rounded-xl border border-amber-300 bg-amber-50 p-5 text-amber-950"><p className="font-black">Contractor admission is not available in this environment yet.</p><p className="mt-1 text-sm">Its database update (D-37) must be applied first.</p></div>
        : <ContractorAdmissionBoard
            role={identity.role}
            canRecommendAnywhere={identity.role === "administrator" || procurementScopes.includes(null)}
            recommendFacilities={(sites.data ?? []).map((row) => row as { id: string; name: string }).filter((site) => identity.role === "administrator" || identity.role === "facility_manager" || isPm(site.id))}
            vendors={(vendors.data ?? []).map((row) => row as { id: string; name: string; trade: string | null })}
            requests={requestViews}
            admissions={admissionViews}
            people={(people.data ?? []).map((row) => row as { id: string; display_name: string | null; role: string })}
            managers={(managers.data ?? []).map((raw) => { const row = raw as { id: string; profile_id: string; facility_id: string | null }; return { id: row.id, profileId: row.profile_id, person: nameOf.get(row.profile_id) ?? "—", scope: row.facility_id ? siteName.get(row.facility_id) ?? "Facility" : "Company-wide (all facilities)", facilityId: row.facility_id }; })}
            sites={(sites.data ?? []).map((row) => row as { id: string; name: string })}
          />}
    </main>
  );
}
