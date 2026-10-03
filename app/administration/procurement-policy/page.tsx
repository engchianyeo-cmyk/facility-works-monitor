import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import ProcurementPolicy from "@/components/administration/procurement-policy";

export const revalidate = 0;
export default async function ProcurementPolicyPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/procurement-policy");
  if (!["facility_manager", "administrator"].includes(identity.role)) return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>Only Facility Manager and Administrator may change company procurement policy.</p></main>;
  const supabase = await createClient();
  const [current, history] = await Promise.all([
    supabase.from("procurement_company_policy").select("version_id").eq("singleton", true).single(),
    supabase.from("procurement_policy_versions").select("id,low_value_threshold,change_reason,created_at,changed_by").order("created_at", { ascending: false }),
  ]);
  const policy = history.data?.find(row => row.id === current.data?.version_id);
  return <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
    <h1 className="text-3xl font-black">Company procurement policy</h1>
    {!policy || current.error || history.error ? <p role="alert">Procurement policy is unavailable in this environment.</p> : <>
      <ProcurementPolicy key={policy.id} versionId={policy.id} threshold={Number(policy.low_value_threshold)} />
      <section><h2 className="text-xl font-bold">Policy change history</h2><ul className="mt-4 space-y-3">{history.data?.map(row => <li key={row.id} className="rounded border p-4"><p className="font-bold">S${Number(row.low_value_threshold).toFixed(2)} · {new Date(row.created_at).toLocaleString("en-SG", { timeZone: "Asia/Singapore" })} (Singapore)</p><p>{row.change_reason}</p><p className="text-xs text-slate-600">Changed by: {row.changed_by ?? "Initial company policy"} · Version: {row.id}</p></li>)}</ul></section>
    </>}
  </main>;
}
