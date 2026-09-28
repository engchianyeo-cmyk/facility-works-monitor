import { NextRequest } from "next/server";
import { POST as transition } from "@/app/api/work-orders/[id]/transition/route";

type RouteContext = { params: Promise<{ id: string }> };
const LEGACY_ACTIONS: Record<string, string> = {
  approve: "approve",
  start: "start",
  complete: "complete",
  reject: "cancel",
};

export async function PATCH(request: NextRequest, context: RouteContext) {
  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; }
  catch {
    body = {};
  }
  const action = LEGACY_ACTIONS[String(body.action ?? "")] ?? String(body.action ?? "");
  const adapterRequest = new NextRequest(request.url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      ...body,
      action,
      reason: action === "cancel" ? body.note : body.reason,
    }),
  });
  return transition(adapterRequest, context);
}
