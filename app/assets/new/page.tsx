import Link from "next/link";
import { redirect } from "next/navigation";
import AssetForm from "@/components/assets/asset-form";
import { getCurrentIdentity } from "@/lib/auth";
import { canCreateAsset, type AssetSystemSummary } from "@/lib/assets/types";
import { createClient } from "@/lib/supabase/server";

export default async function NewAssetPage() {
  const identity = await getCurrentIdentity(); if (!identity) redirect("/login?next=/assets/new"); if (!canCreateAsset(identity.role)) redirect("/assets");
  const supabase = await createClient(); const [systems, departments, teams] = await Promise.all([supabase.from("asset_systems").select("id,system_code,name,site,is_active").eq("is_active", true).order("system_code"), supabase.from("departments").select("id,code,name").eq("is_active", true).is("deleted_at", null).order("name"), supabase.from("maintenance_teams").select("id,name").eq("is_active", true).is("deleted_at", null).order("name")]);
  return <main className="mx-auto max-w-4xl space-y-6 p-4 sm:p-6 lg:p-8"><Link href="/assets" className="text-sm font-bold text-blue-700">← Asset Registry</Link><div><p className="text-xs font-black uppercase tracking-widest text-blue-700">Governed master record</p><h1 className="text-3xl font-black">Register Asset</h1><p className="mt-2 text-sm text-slate-600">Register one identifiable physical item. Do not use this form for rooms, functional systems, inventory or preventive-maintenance plans.</p></div><AssetForm systems={(systems.data ?? []) as AssetSystemSummary[]} departments={departments.data ?? []} teams={teams.data ?? []} /></main>;
}
