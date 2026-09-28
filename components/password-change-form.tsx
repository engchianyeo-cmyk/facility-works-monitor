"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { MINIMUM_PASSWORD_LENGTH } from "@/lib/auth/password";

export default function PasswordChangeForm({
  required,
  nextPath,
}: {
  required: boolean;
  nextPath: string;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setSubmitting(true);
    const data = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/auth/password/change", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          password: data.get("password"),
          confirmation: data.get("confirmation"),
          next: nextPath,
        }),
      });
      const result = (await response.json()) as { ok?: boolean; error?: string; next?: string };
      if (!response.ok || !result.ok) {
        setError(result.error ?? "The password could not be changed.");
        return;
      }
      router.replace(result.next ?? nextPath);
      router.refresh();
    } catch {
      setError("The password could not be changed. Try again.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={submit} className="mt-6 space-y-4">
      <div>
        <label htmlFor="password" className="text-sm font-medium">New password</label>
        <input id="password" name="password" type="password" autoComplete="new-password" minLength={MINIMUM_PASSWORD_LENGTH} required className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2" />
      </div>
      <div>
        <label htmlFor="confirmation" className="text-sm font-medium">Confirm new password</label>
        <input id="confirmation" name="confirmation" type="password" autoComplete="new-password" minLength={MINIMUM_PASSWORD_LENGTH} required className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2" />
      </div>
      <p className="text-xs text-slate-500">Use at least {MINIMUM_PASSWORD_LENGTH} characters. Passwords are never written to application logs or audit records.</p>
      {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{error}</p>}
      <button type="submit" disabled={submitting} className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-60">
        {submitting ? "Updating…" : required ? "Set password and continue" : "Change password"}
      </button>
    </form>
  );
}
