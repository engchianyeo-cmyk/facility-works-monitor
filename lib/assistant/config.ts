/**
 * D-58 option A: the in-app AI assistant is OFF unless both are set on the server (Vercel environment):
 *   FMW_ASSISTANT_AI=on   and   ANTHROPIC_API_KEY=<the client's own key>
 * Optional: FMW_ASSISTANT_MODEL (default below). The key never reaches the browser.
 */
export const DEFAULT_ASSISTANT_MODEL = "claude-haiku-5-5";
export const ASSISTANT_MAX_QUESTION = 1000;
export const ASSISTANT_HOURLY_LIMIT = 30;

export function assistantAiEnabled(env: Record<string, string | undefined> = process.env): boolean {
  return env.FMW_ASSISTANT_AI?.trim().toLowerCase() === "on" && Boolean(env.ANTHROPIC_API_KEY?.trim());
}

export function assistantModel(env: Record<string, string | undefined> = process.env): string {
  return env.FMW_ASSISTANT_MODEL?.trim() || DEFAULT_ASSISTANT_MODEL;
}

/** Refuse anything that looks like a password, code or card number before it leaves FMWorks. */
export function looksSensitive(text: string): boolean {
  return /\b(password|passcode|otp|one[- ]time code)\b\s*[:=]?\s*\S{4,}/i.test(text) || /\b(?:\d[ -]?){13,19}\b/.test(text);
}
