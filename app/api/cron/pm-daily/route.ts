import { NextResponse } from "next/server";
import { createAdminClient, isAdminConfigured } from "@/lib/supabase/admin";

/**
 * M35 (owner D-67): the once-a-day planned maintenance run, for a scheduler (Vercel's daily schedule on Production,
 * or the database's own scheduler). Only a caller holding CRON_SECRET may start it.
 */
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ ok: false }, { status: 401 });
  if (!isAdminConfigured()) return NextResponse.json({ ok: false, code: "NOT_CONFIGURED" }, { status: 503 });
  const { data, error } = await createAdminClient().rpc("pm_daily_run");
  if (error) return NextResponse.json({ ok: false, code: "RUN_FAILED" }, { status: 503 });
  return NextResponse.json(data);
}
