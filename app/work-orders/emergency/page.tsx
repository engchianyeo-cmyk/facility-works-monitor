import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import EmergencyRecordForm from "@/components/work-orders/emergency-record-form";

// D-36 (6 Nov 2026): field work never waits for the app. Emergency work already carried out is recorded here.
export default async function RecordEmergencyWorkPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/work-orders/emergency");
  if (identity.role !== "technician") redirect("/work-orders");
  const supabase = await createClient();
  const { data: areas } = await supabase.from("facility_areas").select("id,area_code,name,level,drawing_reference,map_x,map_y").eq("active", true).order("name");
  const areaOptions = ((areas ?? []) as Array<{ id: string; area_code: string; name: string; level: string | null; drawing_reference: string | null; map_x: number | null; map_y: number | null }>)
    .map((area) => ({ id: area.id, name: `${area.name}${area.level ? ` · ${area.level}` : ""} (${area.area_code})`, mapped: Boolean(area.drawing_reference && area.map_x !== null && area.map_y !== null) }));
  return (
    <main className="mx-auto max-w-3xl space-y-6 p-6 lg:p-8">
      <div>
        <h1 className="text-3xl font-bold">Record emergency work already done</h1>
        <p className="mt-2 text-sm text-slate-700">
          Fix the emergency first. Then record it here in one go: what happened, where, when, the work done, the hours and the photos.
          The Work Order is created as emergency work assigned to you and sent for physical completion. The Approver reviews it afterwards.
        </p>
        <p className="mt-2 text-sm text-slate-600">Work not yet done? Use <Link href="/work-orders/new" className="font-semibold text-blue-700 underline">New Work Order</Link> instead.</p>
      </div>
      <EmergencyRecordForm areas={areaOptions} />
    </main>
  );
}
