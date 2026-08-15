"use client";

import { useState } from "react";

export default function PasswordRecoveryForm() {
  const [message, setMessage] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    const data = new FormData(event.currentTarget);
    try {
      await fetch("/api/auth/password/recovery", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email: data.get("email") }),
      });
    } finally {
      setMessage("If the address belongs to an eligible account, recovery instructions have been requested. Check your inbox or contact an Administrator.");
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={submit} className="mt-6 space-y-4">
      <div>
        <label htmlFor="email" className="text-sm font-medium">Account email</label>
        <input id="email" name="email" type="email" autoComplete="email" required className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2" />
      </div>
      {message && <p role="status" className="rounded-lg bg-blue-50 p-3 text-sm text-blue-900">{message}</p>}
      <button type="submit" disabled={submitting} className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60">
        {submitting ? "Requesting…" : "Request recovery instructions"}
      </button>
    </form>
  );
}
