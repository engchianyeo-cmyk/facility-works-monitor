export const FMWORKS_VERSION = "1.1";

export type BuildInfo = {
  version: string;
  commit: string;
  shortCommit: string;
  environment: string;
  environmentLabel: string;
};

export function getBuildInfo(): BuildInfo {
  const commit = process.env.VERCEL_GIT_COMMIT_SHA?.trim() || "local";
  const environment = process.env.VERCEL_ENV?.trim().toLowerCase() || "local";
  return {
    version: FMWORKS_VERSION,
    commit,
    shortCommit: commit === "local" ? commit : commit.slice(0, 7),
    environment,
    environmentLabel:
      environment === "production"
        ? "Production"
        : environment === "preview"
          ? "Preview"
          : "Local",
  };
}
