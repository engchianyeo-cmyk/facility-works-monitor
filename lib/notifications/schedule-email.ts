import { after } from "next/server";

/**
 * D-42 (7 Nov 2026): after a Work Order action (or a Finance / notices page load), send the queued emails once the
 * response has gone back, so the person never waits for the mail server. Does nothing until email is configured.
 */
export function scheduleEmailDispatch(): void {
  if (!process.env.EMAIL_SMTP_USER?.trim() || !process.env.EMAIL_SMTP_PASSWORD?.trim()) return;
  try {
    after(async () => {
      const { runEmailDispatch } = await import("@/lib/notifications/email-dispatch");
      await runEmailDispatch();
    });
  } catch {
    // Called outside a request (for example in a test): nothing to schedule.
  }
}
