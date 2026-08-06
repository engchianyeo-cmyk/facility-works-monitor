import { NextRequest } from "next/server";
import { POST as assign } from "@/app/api/work-orders/[id]/assign/route";

type RouteContext = { params: Promise<{ id: string }> };

export async function PATCH(request: NextRequest, context: RouteContext) {
  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; }
  catch { body = {}; }
  const adapterRequest = new NextRequest(request.url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      assignment_type: "technician",
      assignee_id: body.technician_id,
    }),
  });
  return assign(adapterRequest, context);
}
