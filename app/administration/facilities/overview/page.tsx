import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { DEFAULT_ENDORSEMENT_STAGE, endorsementStageLabel, type EndorsementStage } from "@/lib/facility-settings";
import { defaultRoleLabel } from "@/lib/product-terminology";
import { createClient } from "@/lib/supabase/server";

export const revalidate = 0;

// UAT 30 Oct 2026: a view-only overview of every facility the app serves — its users and the
// requirements that are set per facility — before any editing is added here. Setup stays on
// Administration → Facilities.

type Facility = { id: string; code: string; name: string; address: string | null; is_active: boolean };
type Settings = { facility_id: string; designated_approver_id: string | null; endorsement_stage: EndorsementStage };
type Staff = { profile_id: string; display_name: string; email: string | null; role: string; member: boolean; member_since: string | null };
type Area = { facility_id: string; active: boolean; drawing_reference: string | null };
type Drawing = { facility_id: string; code: string; title: string };
type Order = { facility_id: string | null; status: string };
type Person = { id: string; display_name: string | null; email: string | null; role: string };

const FACILITY_ROLES = ["technician", "approver", "supervisor", "facility_manager"] as const;
const CLOSED = new Set(["closed", "cancelled"]);
const money = (value: number) => `S$${value.toLocaleString("en-SG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const since = (value: string | null) => value ? new Date(value).toLocaleDateString("en-SG", { timeZone: "Asia/Singapore", day: "numeric", month: "short", year: "numeric" }) : "—";

function Requirement({ label, value, basis, pending = false }: { label: string; value: string; basis: string; pending?: boolean }) {
  return <tr className="align-top">
    <th scope="row" className="py-2 pr-3 text-left font-semibold text-slate-800">{label}</th>
    <td className={`py-2 pr-3 ${pending ? "text-amber-800" : "text-slate-900"}`}>{value}</td>
    <td className="py-2 text-xs text-slate-500">{basis}</td>
  </tr>;
}

export default async function FacilitiesOverviewPage() {
  const identity = await getCurrentIdentity();
  if (!identity) redirect("/login?next=/administration/facilities/overview");
  if (identity.role !== "administrator") return <main className="p-8"><h1 className="text-2xl font-bold">Access denied</h1><p>Only the Administrator may view all facilities.</p></main>;
  const supabase = await createClient();
  const [facilities, settings, areas, drawings, orders, companyUsers, limitPolicy, limits, procurementPolicy, procurement, vendors] = await Promise.all([
    supabase.from("sites").select("id,code,name,address,is_active").order("is_active", { ascending: false }).order("name"),
    supabase.from("facility_settings").select("facility_id,designated_approver_id,endorsement_stage"),
    supabase.from("facility_areas").select("facility_id,active,drawing_reference"),
    supabase.from("facility_drawings").select("facility_id,code,title").eq("active", true).order("code"),
    supabase.from("work_orders").select("facility_id,status"),
    supabase.from("profiles").select("id,display_name,email,role").in("role", ["administrator", "finance"]).eq("is_active", true).is("deleted_at", null).order("role").order("display_name"),
    supabase.from("work_order_approval_limit_policy").select("version_id").eq("singleton", true).maybeSingle(),
    supabase.from("work_order_approval_limits").select("version_id,role,maximum_amount"),
    supabase.from("procurement_company_policy").select("version_id").eq("singleton", true).maybeSingle(),
    supabase.from("procurement_policy_versions").select("id,low_value_threshold"),
    supabase.from("vendors").select("payment_terms_days").eq("active", true).is("deleted_at", null),
  ]);
  if (facilities.error) {
    return <main className="mx-auto max-w-4xl p-8"><h1 className="text-3xl font-black">All facilities</h1><p role="alert" className="mt-4">The facility overview is unavailable in this environment.</p></main>;
  }
  const facilityRows = (facilities.data ?? []) as Facility[];
  const settingsBy = new Map(((settings.error ? [] : settings.data ?? []) as Settings[]).map((row) => [row.facility_id, row]));
  const areaRows = (areas.error ? [] : areas.data ?? []) as Area[];
  const drawingRows = (drawings.error ? [] : drawings.data ?? []) as Drawing[];
  const orderRows = (orders.error ? [] : orders.data ?? []) as Order[];
  const staffBy = new Map(await Promise.all(facilityRows.map(async (facility) => {
    const result = await supabase.rpc("admin_facility_staff", { p_facility_id: facility.id });
    return [facility.id, ((result.data ?? []) as Staff[]).filter((row) => row.member)] as const;
  })));
  const people = (companyUsers.error ? [] : companyUsers.data ?? []) as Person[];
  const currentLimits = ((limits.error ? [] : limits.data ?? []) as Array<{ version_id: string; role: string; maximum_amount: number | null }>)
    .filter((row) => row.version_id === (limitPolicy.data as { version_id?: string } | null)?.version_id);
  const threshold = ((procurement.error ? [] : procurement.data ?? []) as Array<{ id: string; low_value_threshold: number }>)
    .find((row) => row.id === (procurementPolicy.data as { version_id?: string } | null)?.version_id)?.low_value_threshold;
  const terms = [...new Set(((vendors.error ? [] : vendors.data ?? []) as Array<{ payment_terms_days: number | null }>).map((row) => row.payment_terms_days).filter((days): days is number => days != null))].sort((a, b) => a - b);

  const summary = facilityRows.map((facility) => {
    const staff = staffBy.get(facility.id) ?? [];
    const own = orderRows.filter((row) => row.facility_id === facility.id);
    const facilityAreas = areaRows.filter((row) => row.facility_id === facility.id && row.active);
    return {
      facility, staff,
      settings: settingsBy.get(facility.id),
      areas: facilityAreas.length,
      pinned: facilityAreas.filter((row) => row.drawing_reference).length,
      drawings: drawingRows.filter((row) => row.facility_id === facility.id),
      open: own.filter((row) => !CLOSED.has(row.status)).length,
      closed: own.filter((row) => row.status === "closed").length,
    };
  });

  return <main className="mx-auto max-w-6xl space-y-6 p-4 sm:p-8">
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div>
        <p className="text-sm font-semibold text-blue-700">Administration</p>
        <h1 className="text-3xl font-black">All facilities</h1>
        <p className="mt-1 max-w-3xl text-slate-600">Every facility served by FMWorks, the people assigned to each one, and the requirements set for each facility. View only; changes are made in Facilities setup and are recorded with a reason.</p>
      </div>
      <Link href="/administration/facilities" className="min-h-11 rounded-lg border border-blue-700 px-4 py-2 text-sm font-bold text-blue-700">Facilities setup →</Link>
    </div>

    <section aria-labelledby="summary-heading" className="rounded-xl border bg-white p-5">
      <h2 id="summary-heading" className="text-lg font-bold">Summary ({facilityRows.length} {facilityRows.length === 1 ? "facility" : "facilities"})</h2>
      <div className="mt-3 overflow-x-auto">
        <table className="w-full min-w-[640px] text-sm">
          <thead><tr className="border-b text-left text-xs uppercase text-slate-500">
            <th className="py-2 pr-3">Facility</th><th className="py-2 pr-3">Status</th><th className="py-2 pr-3 text-right">Staff</th><th className="py-2 pr-3 text-right">Areas</th>
            <th className="py-2 pr-3 text-right">Drawings</th><th className="py-2 pr-3 text-right">Open Work Orders</th><th className="py-2 text-right">Closed</th>
          </tr></thead>
          <tbody className="divide-y">{summary.map((row) => <tr key={row.facility.id}>
            <td className="py-2 pr-3"><a href={`#facility-${row.facility.id}`} className="font-semibold text-blue-700 hover:underline">{row.facility.name}</a> <span className="text-slate-500">· {row.facility.code}</span></td>
            <td className="py-2 pr-3">{row.facility.is_active ? <span className="rounded bg-emerald-100 px-2 py-0.5 text-xs font-bold text-emerald-800">In use</span> : <span className="rounded bg-slate-200 px-2 py-0.5 text-xs font-bold text-slate-700">Not in use</span>}</td>
            <td className="py-2 pr-3 text-right">{row.staff.length}</td><td className="py-2 pr-3 text-right">{row.areas}</td><td className="py-2 pr-3 text-right">{row.drawings.length}</td>
            <td className="py-2 pr-3 text-right">{row.open}</td><td className="py-2 text-right">{row.closed}</td>
          </tr>)}</tbody>
        </table>
      </div>
      {facilityRows.length === 0 && <p className="mt-3 text-sm text-slate-600">No facilities yet. Add one in Facilities setup.</p>}
    </section>

    {summary.map((row) => {
      const approver = row.staff.find((person) => person.profile_id === row.settings?.designated_approver_id);
      return <section key={row.facility.id} id={`facility-${row.facility.id}`} aria-labelledby={`facility-title-${row.facility.id}`} className="space-y-5 rounded-xl border bg-white p-5 sm:p-6">
        <div>
          <h2 id={`facility-title-${row.facility.id}`} className="text-xl font-bold">{row.facility.name} <span className="text-sm font-normal text-slate-500">· {row.facility.code}</span>
            {!row.facility.is_active && <span className="ml-2 rounded bg-slate-200 px-2 py-0.5 text-xs font-semibold text-slate-700">Not in use</span>}</h2>
          {row.facility.address && <p className="text-sm text-slate-600">{row.facility.address}</p>}
        </div>

        <div>
          <h3 className="font-semibold">Users of this facility ({row.staff.length})</h3>
          {row.staff.length === 0 ? <p className="mt-2 text-sm text-amber-800">No staff assigned yet.</p> : <div className="mt-2 overflow-x-auto"><table className="w-full min-w-[560px] text-sm">
            <thead><tr className="border-b text-left text-xs uppercase text-slate-500"><th className="py-2 pr-3">Role</th><th className="py-2 pr-3">Name</th><th className="py-2 pr-3">Email</th><th className="py-2">Assigned since</th></tr></thead>
            <tbody className="divide-y">{FACILITY_ROLES.flatMap((role) => row.staff.filter((person) => person.role === role)).map((person) => <tr key={person.profile_id}>
              <td className="py-2 pr-3">{defaultRoleLabel(person.role)}{person.profile_id === row.settings?.designated_approver_id && <span className="ml-2 rounded bg-blue-100 px-2 py-0.5 text-xs font-bold text-blue-800">Designated Approver</span>}</td>
              <td className="py-2 pr-3 font-semibold">{person.display_name}</td><td className="py-2 pr-3 text-slate-600">{person.email ?? "—"}</td><td className="py-2 text-slate-600">{since(person.member_since)}</td>
            </tr>)}</tbody>
          </table></div>}
        </div>

        <div>
          <h3 className="font-semibold">Requirements for this facility</h3>
          <div className="mt-2 overflow-x-auto"><table className="w-full min-w-[560px] text-sm"><tbody className="divide-y">
            <Requirement label="Designated Approver" value={approver?.display_name ?? "Not designated — any Approver of this facility"} basis="D-02, D-04" pending={!approver} />
            <Requirement label="Second Technician endorsement" value={endorsementStageLabel(row.settings?.endorsement_stage ?? DEFAULT_ENDORSEMENT_STAGE)} basis="D-11, D-20" />
            <Requirement label="Independent checker" value="Technician 2 verifies the work and materials against the final quotation, the site evidence and, with competing quotations, the basis of the award" basis="D-25" />
            <Requirement label="Areas" value={`${row.areas} in use · ${row.pinned} pinned on layout drawings`} basis="D-17" pending={row.areas === 0} />
            <Requirement label="Layout drawings" value={row.drawings.length ? row.drawings.map((drawing) => `${drawing.code} ${drawing.title}`).join(" · ") : "None uploaded — the mock-up drawings FW-001 to FW-005 are used"} basis="D-17" pending={row.drawings.length === 0} />
            <Requirement label="Archive closed Work Orders after" value="Not set yet — Stage 2" basis="D-18 (each facility's practice)" pending />
            <Requirement label="Off-site copy frequency" value="Not set yet — Stage 2" basis="D-18 (each facility's practice)" pending />
            <Requirement label="Work Orders" value={`${row.open} open · ${row.closed} closed`} basis="Register" />
          </tbody></table></div>
        </div>
      </section>;
    })}

    <section aria-labelledby="company-heading" className="space-y-4 rounded-xl border border-slate-300 bg-slate-50 p-5 sm:p-6">
      <div>
        <h2 id="company-heading" className="text-xl font-bold">Company-wide (applies to every facility)</h2>
        <p className="mt-1 text-sm text-slate-600">These are set once for the company today. Tell us if any should differ by facility.</p>
      </div>
      <div className="overflow-x-auto"><table className="w-full min-w-[560px] text-sm"><tbody className="divide-y">
        <Requirement label="Approval limits" value={currentLimits.length ? currentLimits.map((limit) => `${defaultRoleLabel(limit.role)} up to ${limit.maximum_amount == null ? "no limit" : money(Number(limit.maximum_amount))}`).join(" · ") : "Not configured"} basis="Approval Limits" pending={!currentLimits.length} />
        <Requirement label="Quotations required" value={threshold != null ? `One quotation below ${money(Number(threshold))}; three at or above` : "Policy not assigned"} basis="Procurement policy" pending={threshold == null} />
        <Requirement label="Contractor payment terms" value={terms.length ? terms.map((days) => `${days} days`).join(" · ") + " from the date Finance receives the invoice" : "Not set"} basis="Contractors" pending={!terms.length} />
      </tbody></table></div>
      <div>
        <h3 className="font-semibold">Company-wide users ({people.length})</h3>
        {people.length === 0 ? <p className="mt-2 text-sm text-slate-600">None listed.</p> : <ul className="mt-2 divide-y rounded border bg-white text-sm">{people.map((person) => <li key={person.id} className="flex flex-wrap gap-3 px-3 py-2">
          <span className="w-32 text-slate-600">{defaultRoleLabel(person.role)}</span><span className="font-semibold">{person.display_name ?? "—"}</span><span className="text-slate-600">{person.email ?? ""}</span>
        </li>)}</ul>}
      </div>
    </section>
  </main>;
}
