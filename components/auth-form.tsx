"use client";

import { createClient } from "@/lib/supabase/client";
import { useState } from "react";
import { useRouter } from "next/navigation";

function logSupabaseAuthError(
  operation: "sign-in" | "sign-up",
  error: {
    status?: number;
    code?: string;
    message: string;
    name?: string;
  },
) {
  console.error(`Supabase ${operation} error`, {
    status: error.status ?? null,
    code: error.code ?? null,
    message: error.message,
    name: error.name ?? null,
  });
}

type AuthFormProps = {
  mode: "login" | "register";
  nextPath?: string;
  registrationRole?: "reviewer" | "technician";
};

export default function AuthForm({
  mode,
  nextPath = "/works",
  registrationRole = "reviewer",
}: AuthFormProps) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setMessage(null);
    setSubmitting(true);

    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim();
    const password = String(form.get("password") ?? "");
    const supabase = createClient();

    try {
      if (mode === "login") {
        const { error: signInError } = await supabase.auth.signInWithPassword({
          email,
          password,
        });
        if (signInError) {
          logSupabaseAuthError("sign-in", signInError);
          const lowerMessage = signInError.message.toLowerCase();
          setError(
            lowerMessage.includes("email not confirmed")
              ? "Confirm your email before signing in. Check your inbox for the confirmation link."
              : lowerMessage.includes("rate limit")
                ? "Too many attempts. Wait a few minutes before trying again."
                : signInError.message,
          );
          return;
        }
        const completeUrl = new URL("/auth/complete", window.location.origin);
        completeUrl.searchParams.set("next", nextPath);
        router.replace(`${completeUrl.pathname}${completeUrl.search}`);
        router.refresh();
        return;
      }

      const displayName = String(form.get("display_name") ?? "").trim();
      const department = String(form.get("department") ?? "").trim();
      const tradeDiscipline = String(
        form.get("trade_discipline") ?? "",
      ).trim();
      const contactNumber = String(form.get("contact_number") ?? "").trim();
      const confirmPassword = String(form.get("confirm_password") ?? "");
      const responsibilitiesAccepted =
        form.get("responsibilities_accepted") === "on";

      if (!displayName) {
        setError("Display name is required.");
        return;
      }
      if (!department) {
        setError(
          registrationRole === "technician"
            ? "Department or company is required."
            : "Department is required.",
        );
        return;
      }
      if (registrationRole === "technician" && !tradeDiscipline) {
        setError("Trade or technical discipline is required.");
        return;
      }
      if (password.length < 8) {
        setError("Password must contain at least 8 characters.");
        return;
      }
      if (password !== confirmPassword) {
        setError("Passwords do not match.");
        return;
      }
      if (!responsibilitiesAccepted) {
        setError(
          "Accept the responsibilities and access limitations before registering.",
        );
        return;
      }

      const callbackUrl = new URL("/auth/callback", window.location.origin);
      callbackUrl.searchParams.set("next", nextPath);

      const { data, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: callbackUrl.toString(),
          data: {
            display_name: displayName,
            department,
            public_signup_role: registrationRole,
            trade_discipline:
              registrationRole === "technician" ? tradeDiscipline : null,
            contact_number:
              registrationRole === "technician" && contactNumber
                ? contactNumber
                : null,
            account_terms_accepted: true,
          },
        },
      });
      if (signUpError) {
        logSupabaseAuthError("sign-up", signUpError);
        const lowerMessage = signUpError.message.toLowerCase();
        setError(
          lowerMessage.includes("rate limit")
            ? "Too many registration attempts. Wait a few minutes before trying again."
            : signUpError.message,
        );
        return;
      }

      if (data.session) {
        const completeUrl = new URL("/auth/complete", window.location.origin);
        completeUrl.searchParams.set("next", nextPath);
        router.replace(`${completeUrl.pathname}${completeUrl.search}`);
        router.refresh();
      } else {
        setMessage(
          `Registration received. Check your email to confirm your ${registrationRole === "technician" ? "Technician" : "Reviewer"} account.`,
        );
      }
    } finally {
      setSubmitting(false);
    }
  }

  const inputClass =
    "mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-200";

  return (
    <form onSubmit={handleSubmit} className="mt-6 space-y-4">
      {mode === "register" && (
        <>
          <div>
            <label htmlFor="display_name" className="text-sm font-medium">
              Display name
            </label>
            <input
              id="display_name"
              name="display_name"
              autoComplete="name"
              required
              className={inputClass}
            />
          </div>
          <div>
            <label htmlFor="department" className="text-sm font-medium">
              {registrationRole === "technician"
                ? "Department or company"
                : "Department"}
            </label>
            <input
              id="department"
              name="department"
              autoComplete="organization"
              required
              className={inputClass}
            />
          </div>
          {registrationRole === "technician" && (
            <>
              <div>
                <label
                  htmlFor="trade_discipline"
                  className="text-sm font-medium"
                >
                  Trade or technical discipline
                </label>
                <input
                  id="trade_discipline"
                  name="trade_discipline"
                  required
                  className={inputClass}
                />
              </div>
              <div>
                <label htmlFor="contact_number" className="text-sm font-medium">
                  Contact number{" "}
                  <span className="text-slate-400">(optional)</span>
                </label>
                <input
                  id="contact_number"
                  name="contact_number"
                  type="tel"
                  autoComplete="tel"
                  className={inputClass}
                />
              </div>
            </>
          )}
        </>
      )}

      <div>
        <label htmlFor="email" className="text-sm font-medium">
          Email
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          className={inputClass}
        />
      </div>

      <div>
        <label htmlFor="password" className="text-sm font-medium">
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete={mode === "login" ? "current-password" : "new-password"}
          required
          minLength={8}
          className={inputClass}
        />
      </div>

      {mode === "register" && (
        <>
          <div>
            <label htmlFor="confirm_password" className="text-sm font-medium">
              Confirm password
            </label>
            <input
              id="confirm_password"
              name="confirm_password"
              type="password"
              autoComplete="new-password"
              required
              minLength={8}
              className={inputClass}
            />
          </div>
          <label className="flex items-start gap-3 rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm text-slate-700">
            <input
              type="checkbox"
              name="responsibilities_accepted"
              required
              className="mt-0.5 h-4 w-4 rounded border-slate-300 text-blue-600 focus:ring-blue-500"
            />
            <span>
              I understand the responsibilities and access limitations of this
              account.
            </span>
          </label>
        </>
      )}

      {error && (
        <p role="alert" className="text-sm text-red-700">
          {error}
        </p>
      )}
      {message && (
        <p role="status" className="text-sm text-green-700">
          {message}
        </p>
      )}

      <button
        type="submit"
        disabled={submitting}
        className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {submitting
          ? mode === "login"
            ? "Signing in…"
            : "Registering…"
          : mode === "login"
            ? "Sign in"
            : `Register as a ${
                registrationRole === "technician" ? "Technician" : "Reviewer"
              }`}
      </button>
    </form>
  );
}
