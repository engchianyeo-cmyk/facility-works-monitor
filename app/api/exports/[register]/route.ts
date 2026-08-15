import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createCsv, exportDisplayValue, singaporeTimestamp, type CsvValue } from "@/lib/exports/csv";
import { createClient } from "@/lib/supabase/server";

type RouteContext = { params: Promise<{ register: string }> };
type Row = Record<string, unknown>;

const EXPORT_ROLES = new Set(["approver", "supervisor", "administrator"]);
const REGISTERS = new Set(["work-orders", "assets", "incidents", "pm-outcomes"]);
const value = (row: Row, key: string): CsvValue => {
  const item = row[key];
  return typeof item === "string" || typeof item === "number" || typeof item === "boolean" ? item : null;
};
const related = (row: Row, key: string): Row => {
  const item = row[key];
  const candidate = Array.isArray(item) ? item[0] : item;
  return candidate && typeof candidate === "object" ? candidate as Row : {};
};

function csvResponse(register: string, headers: string[], rows: CsvValue[][]) {
  return new NextResponse(createCsv(headers, rows), {
    status: 200,
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="fmworks-${register}-${new Date().toISOString().slice(0, 10)}.csv"`,
      "cache-control": "private, no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}

export async function GET(_request: Request, context: RouteContext) {
  const identity = await getCurrentIdentity();
  if (!identity) return NextResponse.json({ error: "Authentication required." }, { status: 401 });
  if (!EXPORT_ROLES.has(identity.role)) return NextResponse.json({ error: "Export access denied." }, { status: 403 });
  const { register } = await context.params;
  if (!REGISTERS.has(register)) return NextResponse.json({ error: "Export register not found." }, { status: 404 });

  const supabase = await createClient();
  const asOf = singaporeTimestamp();

  if (register === "work-orders") {
    const { data, error } = await supabase.from("work_orders").select("id,work_order_number,title,site,location,priority,status,source,source_reference,due_date,created_at,updated_at,completed_at,reviewed_at,closed_at,cancelled_at,assigned_type,assigned_to,asset:assets(asset_tag,name)").order("work_order_number");
    if (error) return NextResponse.json({ error: "Work Order export is unavailable." }, { status: 503 });
    const records = (data ?? []) as unknown as Row[];
    const ids = records.map((row) => String(row.id));
    const activity = ids.length
      ? await supabase.from("activity_logs").select("work_order_id,action").in("work_order_id", ids).eq("action", "work_order_returned_for_rework")
      : { data: [], error: null };
    if (activity.error) return NextResponse.json({ error: "Work Order rework counts are unavailable." }, { status: 503 });
    const rework = new Map<string, number>();
    for (const item of (activity.data ?? []) as unknown as Row[]) {
      const id = String(item.work_order_id);
      rework.set(id, (rework.get(id) ?? 0) + 1);
    }
    const headers = ["as_of_asia_singapore","work_order_number","title","site","location","asset_tag","asset_name","priority","status","source","source_reference","assigned_type","assignee_name","due_date","created_at","updated_at","completed_at","reviewed_at","closed_at","cancelled_at","rework_count"];
    return csvResponse(register, headers, records.map((row) => { const asset = related(row, "asset"); return [asOf,value(row,"work_order_number"),value(row,"title"),value(row,"site"),value(row,"location"),value(asset,"asset_tag"),value(asset,"name"),value(row,"priority"),value(row,"status"),value(row,"source"),value(row,"source_reference"),value(row,"assigned_type"),exportDisplayValue(value(row,"assigned_to")),value(row,"due_date"),value(row,"created_at"),value(row,"updated_at"),value(row,"completed_at"),value(row,"reviewed_at"),value(row,"closed_at"),value(row,"cancelled_at"),rework.get(String(row.id)) ?? 0]; }));
  }

  if (register === "assets") {
    const { data, error } = await supabase.from("assets").select("asset_tag,name,asset_type,criticality,lifecycle_status,site,building,floor_zone,room,location,manufacturer,model,serial_number,in_service_date,warranty_expiry,out_of_service_at,system:asset_systems(system_code,name),department:departments(code,name),responsible_team:maintenance_teams(name)").order("asset_tag");
    if (error) return NextResponse.json({ error: "Asset export is unavailable." }, { status: 503 });
    const headers = ["as_of_asia_singapore","asset_tag","name","asset_type","system_code","system_name","criticality","lifecycle_status","site","building","floor_zone","room","location","department_code","department_name","responsible_team","manufacturer","model","serial_number","in_service_date","warranty_expiry","out_of_service_at"];
    return csvResponse(register, headers, ((data ?? []) as unknown as Row[]).map((row) => { const system=related(row,"system"), department=related(row,"department"), team=related(row,"responsible_team"); return [asOf,value(row,"asset_tag"),value(row,"name"),value(row,"asset_type"),value(system,"system_code"),value(system,"name"),value(row,"criticality"),value(row,"lifecycle_status"),value(row,"site"),value(row,"building"),value(row,"floor_zone"),value(row,"room"),value(row,"location"),value(department,"code"),value(department,"name"),value(team,"name"),value(row,"manufacturer"),value(row,"model"),value(row,"serial_number"),value(row,"in_service_date"),value(row,"warranty_expiry"),value(row,"out_of_service_at")]; }));
  }

  if (register === "incidents") {
    const { data, error } = await supabase.from("incidents").select("incident_number,incident_type,severity,status,location,description,reported_at,acknowledgement_deadline,acknowledged_at,rescue_started_at,safe_at,recovery_started_at,closed_at,assignment_type,asset:assets(asset_tag,name),assigned_technician:profiles!incidents_assigned_technician_id_fkey(display_name),assigned_team:maintenance_teams(name),incident_commander:profiles!incidents_incident_commander_id_fkey(display_name)").order("reported_at");
    if (error) return NextResponse.json({ error: "Incident export is unavailable." }, { status: 503 });
    const headers = ["as_of_asia_singapore","incident_number","incident_type","severity","status","site_location","description","asset_tag","asset_name","assignment_type","assigned_technician","assigned_team","incident_commander","reported_at","acknowledgement_deadline","acknowledged_at","rescue_started_at","safe_at","recovery_started_at","closed_at"];
    return csvResponse(register, headers, ((data ?? []) as unknown as Row[]).map((row) => { const asset=related(row,"asset"), technician=related(row,"assigned_technician"), team=related(row,"assigned_team"), commander=related(row,"incident_commander"); return [asOf,value(row,"incident_number"),value(row,"incident_type"),value(row,"severity"),value(row,"status"),value(row,"location"),value(row,"description"),value(asset,"asset_tag"),value(asset,"name"),value(row,"assignment_type"),value(technician,"display_name"),value(team,"name"),value(commander,"display_name"),value(row,"reported_at"),value(row,"acknowledgement_deadline"),value(row,"acknowledged_at"),value(row,"rescue_started_at"),value(row,"safe_at"),value(row,"recovery_started_at"),value(row,"closed_at")]; }));
  }

  const [{ data, error }, complianceResult] = await Promise.all([
    supabase.from("pm_occurrences").select("id,occurrence_number,original_due_date,current_due_date,generation_status,generation_attempts,last_generation_error_code,cancellation_reason,cancelled_at,requirement:maintenance_requirements(requirement_number,state),revision:maintenance_requirement_revisions(revision_number,title,maintenance_type),asset:assets(asset_tag,name),work_order:work_orders(work_order_number,status,completed_at,reviewed_at,closed_at)").order("current_due_date"),
    supabase.from("pm_occurrence_compliance").select("id,compliance_state,deferral_count"),
  ]);
  if (error || complianceResult.error) return NextResponse.json({ error: "PM outcomes export is unavailable." }, { status: 503 });
  const compliance = new Map(((complianceResult.data ?? []) as unknown as Row[]).map((row) => [String(row.id), row]));
  const headers = ["as_of_asia_singapore","requirement_number","requirement_state","revision_number","requirement_title","maintenance_type","occurrence_number","asset_tag","asset_name","original_due_date","current_due_date","pm_outcome","deferral_count","generation_status","generation_attempts","last_generation_error_code","work_order_number","work_order_status","work_order_completed_at","work_order_reviewed_at","work_order_closed_at","cancellation_reason","cancelled_at"];
  return csvResponse(register, headers, ((data ?? []) as unknown as Row[]).map((row) => { const requirement=related(row,"requirement"), revision=related(row,"revision"), asset=related(row,"asset"), work=related(row,"work_order"), outcome=compliance.get(String(row.id))??{}; return [asOf,value(requirement,"requirement_number"),value(requirement,"state"),value(revision,"revision_number"),value(revision,"title"),value(revision,"maintenance_type"),value(row,"occurrence_number"),value(asset,"asset_tag"),value(asset,"name"),value(row,"original_due_date"),value(row,"current_due_date"),value(outcome,"compliance_state"),value(outcome,"deferral_count"),value(row,"generation_status"),value(row,"generation_attempts"),value(row,"last_generation_error_code"),value(work,"work_order_number"),value(work,"status"),value(work,"completed_at"),value(work,"reviewed_at"),value(work,"closed_at"),value(row,"cancellation_reason"),value(row,"cancelled_at")]; }));
}
