import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { canCreate } from "@/lib/work-orders/permissions";
import WorkOrderForm from "@/components/work-orders/work-order-form";

export default async function NewWorkOrderPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/work-orders/new");
  if (!canCreate(identity.role)) redirect("/work-orders");
  const supabase = await createClient();
  const [{ data: categories }, { data: departments }, { data: assets }, { data: people }, { data: facilities }, { data: areas }] = await Promise.all([
    supabase.from("categories").select("id,name").order("name"),
    supabase.from("departments").select("id,code,name").eq("is_active", true).is("deleted_at", null).order("name"),
    supabase.from("assets").select("id,asset_tag,name,asset_type,criticality,lifecycle_status,site,location,system:asset_systems(name,system_code)").neq("lifecycle_status", "decommissioned").order("asset_tag"),
    supabase.rpc("work_order_people_directory"),
    supabase.from("sites").select("id,name").eq("is_active", true).order("name"),
    supabase.from("facility_areas").select("id,area_code,name,level,facility_id,drawing_reference,map_x,map_y").eq("active", true).order("name"),
  ]);
  const areaOptions = ((areas ?? []) as Array<{ id: string; area_code: string; name: string; level: string | null; facility_id: string | null; drawing_reference: string | null; map_x: number | null; map_y: number | null }>)
    .map((area) => ({ id: area.id, name: `${area.name}${area.level ? ` · ${area.level}` : ""} (${area.area_code})`, facilityId: area.facility_id, mapped: Boolean(area.drawing_reference && area.map_x !== null && area.map_y !== null) }));
  const directory = ((people ?? []) as Array<{ id: string; display_name: string; role: string }>).filter((person) => person.id !== identity.userId).map((person) => ({ id: person.id, name: person.display_name, role: person.role }));
  return <main className="mx-auto max-w-3xl space-y-6 p-6 lg:p-8"><div><h1 className="text-3xl font-bold">New Work Order</h1><p className="mt-1 text-sm text-slate-500">Create the Work Order as a draft, attach the supporting material and quotation, then submit it for approval.</p></div><WorkOrderForm categories={categories ?? []} departments={departments ?? []} assets={(assets ?? []) as never[]} role={identity.role} people={directory} facilities={(facilities ?? []).map((facility) => ({ id: facility.id, name: facility.name }))} areas={areaOptions} /></main>;
}
