import { NextResponse } from "next/server";
import { previewIdentityResponse } from "@/lib/preview-environment-identity";

export const dynamic = "force-dynamic";

export async function GET() {
  const result = previewIdentityResponse(
    process.env.VERCEL_ENV,
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
  );
  if (!result) return new NextResponse(null, { status: 404 });
  return NextResponse.json(result, { headers: { "Cache-Control": "no-store" } });
}
