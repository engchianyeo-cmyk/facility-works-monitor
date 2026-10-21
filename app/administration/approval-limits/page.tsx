import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import ApprovalLimits from "@/components/administration/approval-limits";
import { roleLabel } from "@/lib/product-terminology";

export const revalidate = 0;

const money = (value: number | null) => value === null ? "No limit" : `S$${new Intl.NumberFormat("en-SG", { minimumFractionDigits: 2 }).format(value)}`;

export default async function ApprovalLimitsPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/approval-limits");
  if (identity.role !== "administrator") return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>Only the Administrator may change approval limits.</p></main>;
  const supabase = await createClient();
  const [policy, versions, limits] = await Promise.all([
    supabase.from("work_order_approval_limit_policy").select("version_id").eq("singleton", true).single(),
    supabase.from("work_order_approval_limit_versions").select("id,change_reason,created_at").order("created_at", { ascending: false }),
    supabase.from("work_order_approval_limits").select("version_id,role,maximum_amount"),
  ]);
  if (policy.error || versions.error || limits.error || !policy.data) {
    return <main className="mx-auto max-w-4xl p-8"><h1 className="text-3xl font-black">Approval limits</h1><p role="alert" className="mt-4">Approval limits are unavailable in this environment.</p></main>;
  }
  const byVersion = (versionId: string) => Object.fromEntries((limits.data ?? []).filter((row) => row.version_id === versionId).map((row) => [row.role, row.maximum_amount === null ? null : Number(row.maximum_amount)]));
  const current = byVersion(policy.data.version_id);
  return <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
    <h1 className="text-3xl font-black">Approval limits</h1>
    <ApprovalLimits key={policy.data.version_id} versionId={policy.data.version_id} limits={current} />
    <section>
      <h2 className="text-xl font-bold">Change history</h2>
      <ul className="mt-4 space-y-3">
        {(versions.data ?? []).map((version) => {
          const values = byVersion(version.id);
          return <li key={version.id} className="rounded border bg-white p-4">
            <p className="font-bold">{["approver", "supervisor", "facility_manager"].map((role) => `${roleLabel(role)} ${money(values[role] ?? null)}`).join(" · ")}</p>
            <p className="mt-1 text-sm text-slate-600">{new Date(version.created_at).toLocaleString("en-SG")} — {version.change_reason}</p>
          </li>;
        })}
      </ul>
    </section>
  </main>;
}
