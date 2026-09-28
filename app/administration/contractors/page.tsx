import { redirect } from "next/navigation";
import ContractorManagement from "@/components/administration/contractor-management";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

export const revalidate = 0;

export default async function ContractorsPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/contractors");
  if (!["supervisor", "facility_manager", "administrator"].includes(identity.role)) {
    return <main className="mx-auto max-w-xl p-8"><div className="rounded-xl border border-red-200 bg-red-50 p-6"><h1 className="text-2xl font-bold text-red-900">Access denied</h1><p className="mt-2 text-red-800">Contractor administration is limited to Supervisor, Facility Manager and Administrator roles.</p></div></main>;
  }

  const supabase = await createClient();
  const [vendorResult, categoryResult, rateResult] = await Promise.all([
    supabase.from("vendors").select("id,name,trade,contact_name,contact_email,contact_phone,vendor_type,emergency_available,payment_terms_days").eq("active", true).is("deleted_at", null).order("name"),
    supabase.from("contractor_service_categories").select("id,code,name").eq("active", true).order("name"),
    supabase.from("contractor_rate_items").select("id,vendor_id,cost_type,description,unit,normal_unit_rate,emergency_unit_rate,currency,effective_from,effective_to").eq("active", true).order("effective_from", { ascending: false }),
  ]);

  const unavailable = vendorResult.error || categoryResult.error || rateResult.error;

  return <main className="mx-auto max-w-7xl space-y-6 p-4 sm:p-8">
    <header><p className="text-sm font-black uppercase tracking-widest text-blue-700">Administration</p><h1 className="text-3xl font-black">Contractors & Agreed Rates</h1><p className="mt-2 max-w-3xl text-slate-600">Maintain nominated service companies, manpower providers and pre-agreed unit rates used for normal and emergency Work Orders.</p></header>
    {unavailable ? <div className="rounded-xl border border-amber-300 bg-amber-50 p-5 text-amber-950"><p className="font-black">Contractor controls are not available in this environment yet.</p><p className="mt-1 text-sm">Migration 0024 must be applied to the active Preview database before this administration page can be used.</p></div> : <ContractorManagement vendors={vendorResult.data ?? []} categories={categoryResult.data ?? []} rates={rateResult.data ?? []} />}
  </main>;
}
