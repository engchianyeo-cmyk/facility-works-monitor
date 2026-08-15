import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { incidentTransportFailure, type IncidentRpcResult } from "@/lib/incidents/api";
import { canReportIncident } from "@/lib/incidents/permissions";
import { isIncidentSeverity, isIncidentStatus, isIncidentType, UUID_PATTERN } from "@/lib/incidents/validation";
import type { IncidentRecord } from "@/lib/incidents/types";
import { createClient } from "@/lib/supabase/server";
import { errorResponse } from "@/lib/work-orders/api";

type QueryResult = { data: IncidentRecord[] | null; error: unknown; count: number | null };
const TERMINAL = ["closed", "cancelled"];

// Supabase's fluent builder changes its generic type after each filter.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function applyFilters(query: any, request: NextRequest, identity: Awaited<ReturnType<typeof getCurrentIdentity>>) {
  const params = request.nextUrl.searchParams;
  const status = params.get("status");
  const severity = params.get("severity");
  const incidentType = params.get("incident_type");
  if (status) query = query.eq("status", status);
  if (severity) query = query.eq("severity", severity);
  if (incidentType) query = query.eq("incident_type", incidentType);
  const search = params.get("search")?.replaceAll(/[,%()]/g, " ").trim();
  if (search) query = query.or(`incident_number.ilike.%${search}%,location.ilike.%${search}%,description.ilike.%${search}%`);
  const responder = params.get("assigned_responder");
  if (responder === "unassigned") query = query.is("assigned_technician_id", null).is("assigned_team_id", null);
  else if (responder === "mine" && identity) query = query.eq("assigned_technician_id", identity.userId);
  else if (responder && UUID_PATTERN.test(responder)) query = query.or(`assigned_technician_id.eq.${responder},assigned_team_id.eq.${responder}`);
  return query;
}

async function listBucket(supabase: Awaited<ReturnType<typeof createClient>>, request: NextRequest, identity: NonNullable<Awaited<ReturnType<typeof getCurrentIdentity>>>, bucket: "emergency" | "active" | "terminal") {
  let query = supabase.from("incidents").select("*", { count: "exact" });
  query = applyFilters(query, request, identity);
  if (!request.nextUrl.searchParams.get("status") && !request.nextUrl.searchParams.get("active")) {
    if (bucket === "emergency") query = query.not("status", "in", `(${TERMINAL.join(",")})`).eq("severity", "emergency");
    if (bucket === "active") query = query.not("status", "in", `(${TERMINAL.join(",")})`).neq("severity", "emergency");
    if (bucket === "terminal") query = query.in("status", TERMINAL);
  }
  return await query.order("reported_at", { ascending: false }) as QueryResult;
}

export async function GET(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  const params = request.nextUrl.searchParams;
  const status = params.get("status"); const severity = params.get("severity"); const type = params.get("incident_type");
  if (status && !isIncidentStatus(status)) return errorResponse("VALIDATION_ERROR", "Incident status is invalid.");
  if (severity && !isIncidentSeverity(severity)) return errorResponse("VALIDATION_ERROR", "Incident severity is invalid.");
  if (type && !isIncidentType(type)) return errorResponse("VALIDATION_ERROR", "Incident type is invalid.");
  if (params.get("active") && !["true", "false"].includes(params.get("active")!)) return errorResponse("VALIDATION_ERROR", "Active filter is invalid.");
  const responder = params.get("assigned_responder");
  if (responder && !["mine", "unassigned"].includes(responder) && !UUID_PATTERN.test(responder)) return errorResponse("VALIDATION_ERROR", "Assigned responder filter is invalid.");

  const page = Math.max(1, Number.parseInt(params.get("page") ?? "1", 10) || 1);
  const pageSize = Math.min(100, Math.max(1, Number.parseInt(params.get("page_size") ?? "20", 10) || 20));
  const supabase = await createClient();
  let results: QueryResult[];
  if (status || params.get("active")) {
    let query = applyFilters(supabase.from("incidents").select("*", { count: "exact" }), request, identity);
    if (!status && params.get("active") === "true") query = query.not("status", "in", `(${TERMINAL.join(",")})`);
    if (!status && params.get("active") === "false") query = query.in("status", TERMINAL);
    results = [await query.order("reported_at", { ascending: false }) as QueryResult];
  } else {
    results = await Promise.all([listBucket(supabase, request, identity, "emergency"), listBucket(supabase, request, identity, "active"), listBucket(supabase, request, identity, "terminal")]);
  }
  if (results.some(result => result.error)) return incidentTransportFailure("list");
  const ordered = results.flatMap(result => result.data ?? []);
  const total = results.reduce((sum, result) => sum + (result.count ?? 0), 0);
  const from = (page - 1) * pageSize;
  return NextResponse.json({ ok: true, data: ordered.slice(from, from + pageSize), pagination: { page, page_size: pageSize, total, total_pages: Math.ceil(total / pageSize) } });
}

export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  if (!canReportIncident(identity.role)) return errorResponse("ACCESS_DENIED", "Your role cannot report incidents.", 403);
  let body: Record<string, unknown>;
  try { body = await request.json() as Record<string, unknown>; }
  catch { return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON."); }
  const incidentType = String(body.incident_type ?? "").toLowerCase(); const severity = String(body.severity ?? "emergency").toLowerCase();
  const location = String(body.location ?? "").trim(); const description = String(body.description ?? "").trim();
  if (!isIncidentType(incidentType) || !isIncidentSeverity(severity) || !location || !description || location.length > 200 || description.length > 4000) return errorResponse("VALIDATION_ERROR", "Valid incident type, severity, location, and description are required.");
  try {
    const supabase = await createClient();
    const assetId = String(body.asset_id ?? "").trim();
    if (assetId && !UUID_PATTERN.test(assetId)) return errorResponse("VALIDATION_ERROR", "Asset selection is invalid.");
    const { data, error } = await supabase.rpc("create_incident_with_asset", { p_payload: { incident_type: incidentType, severity, location, description, asset_id: assetId || null } });
    if (error) return incidentTransportFailure("create");
    const result = data as IncidentRpcResult | null;
    if (!result?.ok || !result.incident) return errorResponse(String(result?.code ?? "INTERNAL_ERROR"), String(result?.message ?? "Unable to create the emergency incident."), result?.code === "ACCESS_DENIED" ? 403 : 400);
    const incident = result.incident;
    return NextResponse.json({
      ...result,
      data: incident,
      notification: {
        status: "queued",
        delivery_attempted: false,
        delivered: false,
        provider: null,
      },
    }, { status: 201 });
  } catch { return incidentTransportFailure("create"); }
}
