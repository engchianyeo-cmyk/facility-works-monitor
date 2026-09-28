import { NextResponse } from "next/server";
import { getBuildInfo } from "@/lib/build-info";

export function GET() {
  const build = getBuildInfo();
  return NextResponse.json({
    status: "ok",
    timestamp: new Date().toISOString(),
    build: {
      version: build.version,
      commit: build.commit,
      environment: build.environment,
    },
  });
}
