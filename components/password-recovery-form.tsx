"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

const GENERIC_MESSAGE =
  "If the address belongs to an eligible account, recovery instructions have been requested. Check your inbox or contact an Administrator.";

export default function PasswordRecoveryForm() {
  const [message, setMessage] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setMessage(null);

    const data = new FormData(event.currentTarget);
    const email = String(data.get("email") ?? "").trim();

    try {
      if (email && email.length <= 320) {
        const supabase = createClient();

        const callback = new URL("/auth/callback", window.location.origin);
        callback.searchParams.set("next", "/account/password");

        const { error } = await supabase.auth.resetPasswordForEmail(email, {
          redirectTo: callback.toString(),
        });

        if (error) {
          console.warn("[password-recovery] Recovery request was not accepted", {
            status: error.status,
            code: error.code,
            name: error.name,
          });
        }
      }
    } catch (error) {
      console.warn("[password-recovery] Recovery request failed", {
        name: error instanceof Error ? error.name : "UnknownError",
      });
    } finally {
      // Always return the same message so account existence is not disclosed.
      setMessage(GENERIC_MESSAGE);
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={submit} className="mt-6 space-y-4">
      <div>
        <label htmlFor="email" className="text-sm font-medium">
          Account email
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2"
        />
      </div>

      {message && (
        <p
          role="status"
          className="rounded-lg bg-blue-50 p-3 text-sm text-blue-900"
        >
          {message}
        </p>
      )}

      <button
        type="submit"
        disabled={submitting}
        className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60"
      >
        {submitting ? "Requesting…" : "Request recovery instructions"}
      </button>
    </form>
  );
}