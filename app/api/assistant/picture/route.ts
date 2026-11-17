import { NextResponse } from "next/server";
import { getCurrentAccountIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** D-58: the assistant's custom picture (signed-in people only). SVG is served with a locked-down policy. */
export async function GET() {
  const identity = await getCurrentAccountIdentity();
  if (!identity) return new NextResponse(null, { status: 401 });
  const supabase = await createClient();
  const { data } = await supabase.from("assistant_settings").select("image_data_url").maybeSingle();
  const value = (data as { image_data_url?: string | null } | null)?.image_data_url ?? null;
  const match = value?.match(/^data:(image\/(?:png|jpeg|webp|svg\+xml));base64,([A-Za-z0-9+/=]+)$/);
  if (!match) return new NextResponse(null, { status: 404 });
  return new NextResponse(Buffer.from(match[2], "base64"), {
    headers: {
      "content-type": match[1],
      "cache-control": "private, max-age=86400",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; sandbox",
      "x-content-type-options": "nosniff",
    },
  });
}
