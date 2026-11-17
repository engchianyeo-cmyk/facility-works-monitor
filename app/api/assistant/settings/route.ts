import { NextResponse } from "next/server";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** D-58: the Super-Administrator renames the assistant or replaces its picture (null picture = Ollie again). */
export async function POST(request: Request) {
  const identity = await getCurrentIdentity();
  if (!identity || identity.role !== "administrator") return NextResponse.json({ error: "Only the Super-Administrator can change the assistant." }, { status: 403 });
  const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_assistant_settings", {
    p_display_name: String(body.name ?? ""),
    p_image_data_url: typeof body.image === "string" && body.image ? body.image : null,
  });
  const result = data as { ok?: boolean; message?: string } | null;
  if (error || !result?.ok) return NextResponse.json({ error: result?.message ?? "The assistant could not be changed." }, { status: 409 });
  return NextResponse.json({ ok: true });
}
