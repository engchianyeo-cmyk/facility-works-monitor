import { NextResponse } from "next/server";
import { diagnosePreviewNetwork } from "@/lib/preview-environment-identity";
import { getCurrentIdentity } from "@/lib/auth";

export const dynamic = "force-dynamic";

export async function GET() {
  if (process.env.VERCEL_ENV !== "preview") return new NextResponse(null, { status: 404 });
  const identity = await getCurrentIdentity();
  if (!identity) return new NextResponse(null, { status: 401 });
  if (identity.role !== "administrator") return new NextResponse(null, { status: 403 });
  const result = await diagnosePreviewNetwork(
    process.env.VERCEL_ENV,
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
  );
  if (!result) return new NextResponse(null, { status: 404 });
  return NextResponse.json(result, { headers: { "Cache-Control": "no-store" } });
}
