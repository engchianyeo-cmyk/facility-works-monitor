import { NextRequest, NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { canCreate } from "@/lib/work-orders/permissions";
import { errorResponse, rpcResponse, transportFailure } from "@/lib/work-orders/api";
import type { RpcResult, WorkOrderRecord } from "@/lib/work-orders/types";
import {
  isWorkOrderPriority,
  isWorkOrderSource,
  isWorkOrderStatus,
  validateContactNumber,
  validatePredictiveRanges,
} from "@/lib/work-orders/validation";

const SORT_COLUMNS: Record<string, string> = {
  newest: "created_at",
  oldest: "created_at",
  due_date: "due_date",
  priority: "priority_rank",
  updated: "updated_at",
  work_order_number: "work_order_number",
};

export async function GET(request: NextRequest) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);

  const params = request.nextUrl.searchParams;
  const page = Math.max(1, Number.parseInt(params.get("page") ?? "1", 10) || 1);
  const pageSize = Math.min(100, Math.max(1, Number.parseInt(params.get("page_size") ?? "20", 10) || 20));
  const sort = params.get("sort") ?? "newest";
  const sortColumn = SORT_COLUMNS[sort] ?? SORT_COLUMNS.newest;
  const ascending = sort === "oldest" || params.get("direction") === "asc";
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const status = params.get("status");
  const priority = params.get("priority");
  const source = params.get("source");
  if (status && !isWorkOrderStatus(status)) return errorResponse("VALIDATION_ERROR", "Status filter is invalid.");
  if (priority && !isWorkOrderPriority(priority)) return errorResponse("VALIDATION_ERROR", "Priority filter is invalid.");
  if (source && !isWorkOrderSource(source)) return errorResponse("VALIDATION_ERROR", "Source filter is invalid.");

  const supabase = await createClient();
  let query = supabase
    .from("work_orders")
    .select("*, categories(name), departments(code,name,colour_tag)", { count: "exact" });
  if (identity.role === "technician") {
    query = query.eq("assigned_technician_id", identity.userId);
  }

  const search = params.get("search")?.trim();
  if (search) {
    const safeSearch = search.replaceAll(/[,%()]/g, " ").trim();
    if (safeSearch) query = query.or(`work_order_number.ilike.%${safeSearch}%,title.ilike.%${safeSearch}%,description.ilike.%${safeSearch}%,location.ilike.%${safeSearch}%`);
  }
  if (status) query = query.eq("status", status);
  if (priority) query = query.eq("priority", priority);
  if (source) query = query.eq("source", source);
  const department = params.get("department");
  if (department) query = query.eq("department_id", department);
  const assignment = params.get("assignment");
  if (assignment === "unassigned") {
    query = query.is("assigned_technician_id", null).is("assigned_vendor_id", null).is("assigned_team_id", null);
  } else if (assignment === "mine" && identity.role !== "technician") {
    query = query.eq("assigned_technician_id", identity.userId);
  } else if (assignment === "technician") {
    query = query.not("assigned_technician_id", "is", null);
  } else if (assignment === "vendor") {
    query = query.not("assigned_vendor_id", "is", null);
  } else if (assignment === "team") {
    query = query.not("assigned_team_id", "is", null);
  }
  const dateFrom = params.get("date_from");
  const dateTo = params.get("date_to");
  if (dateFrom) query = query.gte("created_at", `${dateFrom}T00:00:00.000Z`);
  if (dateTo) query = query.lte("created_at", `${dateTo}T23:59:59.999Z`);

  const { data, error, count } = await query
    .order(sortColumn, { ascending, nullsFirst: false })
    .range(from, to);
  if (error) return transportFailure("list");

  return NextResponse.json({
    ok: true,
    data: data ?? [],
    pagination: {
      page,
      page_size: pageSize,
      total: count ?? 0,
      total_pages: Math.ceil((count ?? 0) / pageSize),
    },
  });
}

async function createWorkOrder(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity) return errorResponse("AUTHENTICATION_REQUIRED", "Authentication is required.", 401);
  if (!canCreate(identity.role)) return errorResponse("ACCESS_DENIED", "Your role cannot create work orders.", 403);

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return errorResponse("VALIDATION_ERROR", "Request body must be valid JSON.");
  }
  const title = String(body.title ?? "").trim();
  const location = String(body.location ?? "").trim();
  if (!title || !location) return errorResponse("VALIDATION_ERROR", "Title and location are required.");
  if (body.source !== undefined && !isWorkOrderSource(body.source)) return errorResponse("VALIDATION_ERROR", "Work-order source is invalid.");
  if (body.priority !== undefined && !isWorkOrderPriority(String(body.priority).toLowerCase())) return errorResponse("VALIDATION_ERROR", "Priority is invalid.");
  const contactError = validateContactNumber(body.contact_number);
  if (contactError) return errorResponse("VALIDATION_ERROR", contactError);
  const rangeError = validatePredictiveRanges(body);
  if (rangeError) return errorResponse("VALIDATION_ERROR", rangeError);

  const payload = {
    ...body,
    title,
    location,
    priority: String(body.priority ?? "medium").toLowerCase(),
    source: String(body.source ?? "manual").toLowerCase(),
    status: body.status === "submitted" || body.submit === true ? "submitted" : "draft",
  };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_work_order", { p_payload: payload });
  if (error) return transportFailure("create");
  return rpcResponse(data as RpcResult<WorkOrderRecord> | null, 201);
}

export async function POST(request: Request) {
  try {
    return await createWorkOrder(request);
  } catch {
    return transportFailure("create");
  }
}
