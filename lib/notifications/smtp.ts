import net from "node:net";
import tls from "node:tls";
import { randomUUID } from "node:crypto";

/**
 * D-42 (8 Nov 2026): a small SMTP client for the app's notice emails (Yahoo Mail by default), so no extra package
 * is needed. Port 465 uses TLS from the start; any other port upgrades with STARTTLS. Sign-in is AUTH LOGIN.
 */
export type SmtpOptions = { host: string; port: number; secure: boolean; user: string; pass: string; timeoutMs?: number; tlsOptions?: tls.ConnectionOptions };
export type SmtpMessage = { fromName: string; from: string; to: string; subject: string; text: string; html: string };

const ascii = (value: string) => /^[\x20-\x7e]*$/.test(value);
export const encodeHeader = (value: string) => ascii(value) ? value : `=?UTF-8?B?${Buffer.from(value, "utf8").toString("base64")}?=`;
const base64Lines = (value: string) => Buffer.from(value, "utf8").toString("base64").replace(/.{1,76}/g, "$&\r\n");
const address = (value: string) => {
  const clean = value.trim();
  if (!/^[^\s<>@,;"]+@[^\s<>@,;"]+\.[^\s<>@,;"]+$/.test(clean)) throw new Error("Invalid email address");
  return clean;
};

/** The email as sent: plain text and HTML versions, both base64 so any language and symbol is safe. */
export function buildMime(message: SmtpMessage, messageId: string, date = new Date()): string {
  const boundary = `fmw-${randomUUID()}`;
  const name = message.fromName.replace(/["\\\r\n]/g, "");
  return [
    `From: ${ascii(name) ? `"${name}"` : encodeHeader(name)} <${address(message.from)}>`,
    `To: <${address(message.to)}>`,
    `Subject: ${encodeHeader(message.subject.replace(/[\r\n]+/g, " "))}`,
    `Date: ${date.toUTCString().replace("GMT", "+0000")}`,
    `Message-ID: ${messageId}`,
    "MIME-Version: 1.0",
    "Auto-Submitted: auto-generated",
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    base64Lines(message.text),
    `--${boundary}`,
    "Content-Type: text/html; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    base64Lines(message.html),
    `--${boundary}--`,
    "",
  ].join("\r\n");
}

type Socket = net.Socket | tls.TLSSocket;

class Conversation {
  private buffer = "";
  private waiters: Array<(line: { code: number; text: string } | Error) => void> = [];
  private lines: Array<{ code: number; text: string }> = [];
  private failure: Error | null = null;
  socket: Socket;
  constructor(socket: Socket) { this.socket = socket; this.attach(socket); }
  attach(socket: Socket) {
    this.socket = socket;
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => this.feed(chunk));
    socket.on("error", (error) => this.fail(error));
    socket.on("close", () => this.fail(new Error("Mail server closed the connection")));
  }
  private feed(chunk: string) {
    this.buffer += chunk;
    let end: number;
    let text = "";
    while ((end = this.buffer.indexOf("\r\n")) >= 0) {
      const line = this.buffer.slice(0, end);
      this.buffer = this.buffer.slice(end + 2);
      text += (text ? "\n" : "") + line.slice(4);
      if (line[3] === "-") continue; // more lines of the same reply follow
      const reply = { code: Number(line.slice(0, 3)), text };
      text = "";
      const waiter = this.waiters.shift();
      if (waiter) waiter(reply); else this.lines.push(reply);
    }
  }
  private fail(error: Error) {
    if (this.failure) return;
    this.failure = error;
    for (const waiter of this.waiters.splice(0)) waiter(error);
  }
  reply(): Promise<{ code: number; text: string }> {
    const ready = this.lines.shift();
    if (ready) return Promise.resolve(ready);
    if (this.failure) return Promise.reject(this.failure);
    return new Promise((resolve, reject) => this.waiters.push((value) => value instanceof Error ? reject(value) : resolve(value)));
  }
  async command(line: string | null, expect: number[], label: string): Promise<string> {
    if (line !== null) this.socket.write(`${line}\r\n`);
    const reply = await this.reply();
    if (!expect.includes(reply.code)) throw new Error(`Mail server refused ${label}: ${reply.code} ${reply.text}`.slice(0, 300));
    return reply.text;
  }
}

function connect(options: SmtpOptions): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const socket = options.secure
      ? tls.connect({ host: options.host, port: options.port, servername: options.host, ...options.tlsOptions }, () => resolve(socket))
      : net.connect({ host: options.host, port: options.port }, () => resolve(socket));
    socket.once("error", reject);
  });
}

/** Sends one email and returns its Message-ID. Throws with the mail server's reason if it is refused. */
export async function sendSmtp(options: SmtpOptions, message: SmtpMessage): Promise<string> {
  const timeout = options.timeoutMs ?? 20_000;
  const domain = address(message.from).split("@")[1];
  const messageId = `<${randomUUID()}@${domain}>`;
  const socket = await connect(options);
  socket.setTimeout(timeout, () => socket.destroy(new Error("Mail server did not answer in time")));
  const talk = new Conversation(socket);
  try {
    await talk.command(null, [220], "the connection");
    let features = await talk.command(`EHLO fmworks.app`, [250], "EHLO");
    if (!options.secure) {
      if (!/STARTTLS/i.test(features)) throw new Error("Mail server does not offer STARTTLS");
      await talk.command("STARTTLS", [220], "STARTTLS");
      const upgraded = await new Promise<tls.TLSSocket>((resolve, reject) => {
        socket.removeAllListeners("data");
        const secure = tls.connect({ socket, servername: options.host, ...options.tlsOptions }, () => resolve(secure));
        secure.once("error", reject);
      });
      upgraded.setTimeout(timeout, () => upgraded.destroy(new Error("Mail server did not answer in time")));
      talk.attach(upgraded);
      features = await talk.command("EHLO fmworks.app", [250], "EHLO");
    }
    void features;
    await talk.command("AUTH LOGIN", [334], "sign-in");
    await talk.command(Buffer.from(options.user).toString("base64"), [334], "sign-in (user)");
    await talk.command(Buffer.from(options.pass).toString("base64"), [235], "sign-in (password)");
    await talk.command(`MAIL FROM:<${address(message.from)}>`, [250], "the sender");
    await talk.command(`RCPT TO:<${address(message.to)}>`, [250, 251], "the recipient");
    await talk.command("DATA", [354], "DATA");
    const body = buildMime(message, messageId).replace(/\r\n\./g, "\r\n..");
    await talk.command(`${body}\r\n.`, [250], "the message");
    await talk.command("QUIT", [221], "QUIT").catch(() => undefined);
    return messageId;
  } finally {
    talk.socket.destroy();
  }
}
