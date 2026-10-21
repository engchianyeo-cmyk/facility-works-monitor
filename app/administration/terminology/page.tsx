import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import TerminologyEditor from "@/components/administration/terminology";
import { defaultRoleLabel, defaultWorkOrderStatusLabel, TERMINOLOGY_ROLE_CODES, TERMINOLOGY_STATUS_CODES } from "@/lib/product-terminology";

export const revalidate = 0;

export default async function TerminologyPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/terminology");
  if (identity.role !== "administrator") return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>Only the Administrator may rename roles and stages.</p></main>;
  const supabase = await createClient();
  const { data, error } = await supabase.from("terminology_labels").select("code,label");
  const saved = Object.fromEntries((error ? [] : data ?? []).map((row) => [String(row.code), String(row.label)]));
  const roles = TERMINOLOGY_ROLE_CODES.map((code) => ({ code: `role:${code}`, defaultLabel: defaultRoleLabel(code), label: saved[`role:${code}`] ?? "" }));
  const stages = TERMINOLOGY_STATUS_CODES.map((code) => ({ code: `status:${code}`, defaultLabel: defaultWorkOrderStatusLabel(code), label: saved[`status:${code}`] ?? "" }));
  return <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-8">
    <div><h1 className="text-3xl font-black">Roles and stages</h1><p className="mt-2 text-slate-600">Use your company&apos;s own names. Only the displayed names change; permissions and records stay the same.</p></div>
    {error && <p role="alert">Saved labels could not be loaded.</p>}
    <TerminologyEditor title="Role names" rows={roles} />
    <TerminologyEditor title="Work Order stage names" rows={stages} />
  </main>;
}
