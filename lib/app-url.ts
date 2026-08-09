import "server-only";

export class AppUrlConfigurationError extends Error {
  readonly code = "APP_URL_NOT_CONFIGURED";

  constructor() {
    super("The application URL is not configured for this deployment.");
    this.name = "AppUrlConfigurationError";
  }
}

function origin(value: string | undefined, protocol = "https:") {
  const candidate = value?.trim();
  if (!candidate) return null;
  try {
    const url = new URL(candidate.includes("://") ? candidate : `${protocol}//${candidate}`);
    return url.origin;
  } catch {
    return null;
  }
}

function isLocal(value: string) {
  const hostname = new URL(value).hostname;
  return hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1";
}

export function applicationOrigin(requestUrl?: string) {
  const deployed = Boolean(process.env.VERCEL_ENV);
  const configured = origin(process.env.NEXT_PUBLIC_APP_URL);
  const vercelHost = origin(
    process.env.VERCEL_ENV === "production"
      ? process.env.VERCEL_PROJECT_PRODUCTION_URL ?? process.env.VERCEL_URL
      : process.env.VERCEL_URL,
  );
  const requestOrigin = origin(requestUrl);

  for (const candidate of [configured, vercelHost, requestOrigin]) {
    if (candidate && (!deployed || !isLocal(candidate))) return candidate;
  }

  if (!deployed) return "http://localhost:3000";
  throw new AppUrlConfigurationError();
}

export function applicationCallbackUrl(requestUrl?: string) {
  return new URL("/auth/callback", applicationOrigin(requestUrl)).toString();
}
