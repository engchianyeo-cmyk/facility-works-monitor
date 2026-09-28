import Link from "next/link";
import { redirect } from "next/navigation";
import IncidentForm from "@/components/incidents/incident-form";
import { getCurrentIdentity } from "@/lib/auth";
import { canReportIncident } from "@/lib/incidents/permissions";
import { createClient } from "@/lib/supabase/server";

export default async function NewIncidentPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/incidents/new");
  if (!canReportIncident(identity.role)) redirect("/incidents");
  const supabase = await createClient();
  const { data: assets } = await supabase.from("assets").select("id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,system:asset_systems(name,system_code)").neq("lifecycle_status", "decommissioned").order("asset_tag");
  return <main className="mx-auto max-w-3xl space-y-6 p-6 lg:p-8"><Link href="/incidents" className="text-sm text-slate-600">← Emergency incidents</Link><div><p className="text-sm font-bold uppercase tracking-widest text-red-700">Activate emergency response</p><h1 className="text-3xl font-bold">Report Emergency Incident</h1><p className="mt-2 text-slate-600">This immediately creates an active incident. Notification delivery is non-blocking.</p></div><IncidentForm assets={(assets ?? []) as never[]} /></main>;
}
