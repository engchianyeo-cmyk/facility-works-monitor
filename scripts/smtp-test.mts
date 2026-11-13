// D-42 email check (13 Nov 2026): sends one test email with the app's own mail client (lib/notifications/smtp.ts),
// the same way FMWorks does on Vercel. The app password is read from the FMW_SMTP_PASS variable of this PowerShell
// window only; it is never written to a file.
//   node scripts/smtp-test.mts <to-address>
import { sendSmtp } from "../lib/notifications/smtp.ts";

const to = process.argv[2];
const user = process.env.FMW_SMTP_USER ?? "fmworks.notices@gmail.com";
const pass = (process.env.FMW_SMTP_PASS ?? "").replace(/\s+/g, "");
const host = process.env.FMW_SMTP_HOST ?? "smtp.gmail.com";
const port = Number(process.env.FMW_SMTP_PORT ?? 465);
if (!to || !pass) { console.error("Usage: set FMW_SMTP_PASS first, then: node scripts/smtp-test.mts <to-address>"); process.exit(2); }
console.log(`Sending from ${user} via ${host}:${port} to ${to} ...`);
try {
  const id = await sendSmtp({ host, port, secure: port === 465, user, pass, timeoutMs: 20000 },
    { fromName: "FMWorks notices", from: user, to, subject: "[FMWorks] Email test", text: "If you can read this, FMWorks can send from this account.", html: "<p>If you can read this, <b>FMWorks</b> can send from this account.</p>" });
  console.log(`OK: accepted by the mail server (${id}). Check the inbox and Spam.`);
} catch (error) {
  console.error(`FAILED: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
