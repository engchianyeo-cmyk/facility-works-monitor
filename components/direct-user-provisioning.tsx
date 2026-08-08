"use client";

import { FormEvent, useEffect, useRef, useState } from "react";

const ROLES = [
  "reviewer",
  "initiator",
  "approver",
  "technician",
  "supervisor",
  "administrator",
] as const;

type Role = (typeof ROLES)[number];
type Mode = "create" | "activate_pending";
type Department = { id: string; name: string };

type FormState = {
  display_name: string;
  email: string;
  department_id: string;
  trade_discipline: string;
  contact_number: string;
  temporary_password: string;
  role: Role;
  mode: Mode;
  is_active: boolean;
};

const EMPTY_FORM: FormState = {
  display_name: "",
  email: "",
  department_id: "",
  trade_discipline: "",
  contact_number: "",
  temporary_password: "",
  role: "reviewer",
  mode: "create",
  is_active: true,
};

export default function DirectUserProvisioning() {
  const submissionInFlight = useRef(false);
  const [form, setForm] = useState<FormState>(EMPTY_FORM);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [configurationLoading, setConfigurationLoading] = useState(true);
  const [provisioningConfigured, setProvisioningConfigured] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function loadConfiguration() {
      try {
        const response = await fetch("/api/admin/users/direct", {
          cache: "no-store",
        });
        const result = (await response.json()) as {
          error?: string;
          provisioning_configured?: boolean;
          departments?: Department[];
        };
        if (!response.ok) {
          throw new Error(
            result.error ?? "User provisioning status could not be loaded.",
          );
        }
        if (!cancelled) {
          setDepartments(result.departments ?? []);
          setProvisioningConfigured(result.provisioning_configured === true);
        }
      } catch (loadError) {
        if (!cancelled) {
          setError(
            loadError instanceof Error
              ? loadError.message
              : "User provisioning status could not be loaded.",
          );
        }
      } finally {
        if (!cancelled) setConfigurationLoading(false);
      }
    }
    void loadConfiguration();
    return () => {
      cancelled = true;
    };
  }, []);

  const inputClass =
    "mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-200";

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submissionInFlight.current) return;
    submissionInFlight.current = true;
    setSubmitting(true);
    setMessage(null);
    setError(null);

    try {
      const response = await fetch("/api/admin/users/direct", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(form),
      });

      const result = (await response.json()) as {
        message?: string;
        error?: string;
      };

      if (!response.ok) {
        throw new Error(result.error ?? "Unable to provision user.");
      }

      setMessage(result.message ?? "User provisioned successfully.");
      setForm({ ...EMPTY_FORM, department_id: departments[0]?.id ?? "" });
    } catch (submitError) {
      setError(
        submitError instanceof Error
          ? submitError.message
          : "Unable to provision user.",
      );
    } finally {
      submissionInFlight.current = false;
      setSubmitting(false);
    }
  }

  return (
    <section className="rounded-xl border border-blue-200 bg-blue-50/40 p-5 shadow-sm">
      <div>
        <p className="text-sm font-semibold text-blue-700">
          Enterprise user provisioning
        </p>
        <h2 className="mt-1 text-xl font-bold text-slate-900">
          Create or activate a user immediately
        </h2>
        <p className="mt-2 text-sm text-slate-600">
          This workflow does not send an invitation email. The account is
          confirmed and can sign in immediately with the temporary password.
        </p>
      </div>

      <form
        onSubmit={submit}
        className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
      >
        {!configurationLoading && !provisioningConfigured && (
          <p
            role="alert"
            className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900 sm:col-span-2 lg:col-span-3"
          >
            User provisioning is not configured for this deployment. Ask the
            deployment Administrator to configure privileged server access.
          </p>
        )}
        <label className="text-sm font-medium text-slate-700">
          Action
          <select
            value={form.mode}
            onChange={(event) =>
              setForm({
                ...form,
                mode: event.target.value as Mode,
              })
            }
            className={inputClass}
          >
            <option value="create">Create new active user</option>
            <option value="activate_pending">
              Activate existing pending user
            </option>
          </select>
        </label>

        <label className="text-sm font-medium text-slate-700">
          Display name
          <input
            required
            value={form.display_name}
            onChange={(event) =>
              setForm({ ...form, display_name: event.target.value })
            }
            className={inputClass}
          />
        </label>

        <label className="text-sm font-medium text-slate-700">
          Unique email
          <input
            required
            type="email"
            value={form.email}
            onChange={(event) =>
              setForm({ ...form, email: event.target.value })
            }
            className={inputClass}
          />
        </label>

        <label className="text-sm font-medium text-slate-700">
          Department
          <select
            required
            value={form.department_id}
            onChange={(event) =>
              setForm({ ...form, department_id: event.target.value })
            }
            className={inputClass}
          >
            <option value="">Select an active department</option>
            {departments.map((department) => (
              <option key={department.id} value={department.id}>
                {department.name}
              </option>
            ))}
          </select>
        </label>

        <label className="text-sm font-medium text-slate-700">
          Role
          <select
            value={form.role}
            onChange={(event) =>
              setForm({ ...form, role: event.target.value as Role })
            }
            className={inputClass}
          >
            {ROLES.map((role) => (
              <option key={role} value={role}>
                {role === "initiator"
                  ? "Initiator / requester"
                  : role[0].toUpperCase() + role.slice(1)}
              </option>
            ))}
          </select>
        </label>

        <label className="flex items-center gap-3 self-end rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-700">
          <input
            type="checkbox"
            checked={form.is_active}
            onChange={(event) =>
              setForm({ ...form, is_active: event.target.checked })
            }
            className="h-4 w-4 rounded border-slate-300 text-blue-600"
          />
          Active account
        </label>

        {form.role === "technician" && (
          <label className="text-sm font-medium text-slate-700">
            Trade/discipline
            <input
              required
              value={form.trade_discipline}
              onChange={(event) =>
                setForm({
                  ...form,
                  trade_discipline: event.target.value,
                })
              }
              className={inputClass}
            />
          </label>
        )}

        <label className="text-sm font-medium text-slate-700">
          Contact number
          <input
            type="tel"
            value={form.contact_number}
            onChange={(event) =>
              setForm({ ...form, contact_number: event.target.value })
            }
            className={inputClass}
          />
        </label>

        <label className="text-sm font-medium text-slate-700">
          Temporary password
          <input
            required
            type="password"
            minLength={12}
            autoComplete="new-password"
            value={form.temporary_password}
            onChange={(event) =>
              setForm({
                ...form,
                temporary_password: event.target.value,
              })
            }
            className={inputClass}
          />
          <span className="mt-1 block text-xs text-slate-500">
            Minimum 12 characters.
          </span>
        </label>

        <div className="flex items-end sm:col-span-2 lg:col-span-3">
          <button
            type="submit"
            disabled={
              submitting ||
              configurationLoading ||
              !provisioningConfigured ||
              departments.length === 0
            }
            className="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {configurationLoading
              ? "Checking configuration…"
              : submitting
                ? "Processing…"
                : form.mode === "activate_pending"
                  ? "Activate pending user"
                  : "Create user"}
          </button>
        </div>
      </form>

      {(message || error) && (
        <div
          role={error ? "alert" : "status"}
          className={`mt-4 rounded-lg border p-4 text-sm ${
            error
              ? "border-red-200 bg-red-50 text-red-800"
              : "border-green-200 bg-green-50 text-green-800"
          }`}
        >
          {error ?? message}
        </div>
      )}
    </section>
  );
}
