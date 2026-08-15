"use client";

import { Fragment, useCallback, useEffect, useMemo, useState } from "react";
import { operationalLabel } from "@/lib/product-terminology";

const ROLES = [
  "reviewer",
  "initiator",
  "approver",
  "technician",
  "supervisor",
  "administrator",
] as const;

type Role = (typeof ROLES)[number];

type ManagedUser = {
  id: string;
  display_name: string;
  email: string | null;
  department: string | null;
  department_id: string | null;
  trade_discipline: string | null;
  contact_number: string | null;
  role: Role;
  is_active: boolean;
  deleted_at: string | null;
  password_change_required: boolean;
  created_at: string;
  updated_at: string;
  last_active_at: string | null;
  last_seen_route: string | null;
  last_sign_in_at: string | null;
  email_confirmed_at: string | null;
  presence_status: "online" | "idle" | "offline";
  session_status: string;
};

type Department = { id: string; name: string };

type AuditEntry = {
  id: string;
  action: string;
  actor: string | null;
  note: string | null;
  created_at: string;
};

function formatDate(value: string | null) {
  if (!value) return "Never";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "Unavailable"
    : new Intl.DateTimeFormat("en-SG", {
        dateStyle: "medium",
        timeStyle: "short",
      }).format(date);
}

function auditTargetsUser(entry: AuditEntry, userId: string) {
  if (!entry.note) return false;
  try {
    const note = JSON.parse(entry.note) as { target_user_id?: string };
    return note.target_user_id === userId;
  } catch {
    return false;
  }
}

export default function UserManagement({
  currentUserId,
}: {
  currentUserId: string;
}) {
  const [users, setUsers] = useState<ManagedUser[]>([]);
  const [audit, setAudit] = useState<AuditEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [roleFilter, setRoleFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");
  const [presenceFilter, setPresenceFilter] = useState("all");
  const [sortOrder, setSortOrder] = useState("last_activity");
  const [editing, setEditing] = useState<Record<string, ManagedUser>>({});
  const [activityUserId, setActivityUserId] = useState<string | null>(null);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [provisioningConfigured, setProvisioningConfigured] = useState(false);
  const [authDirectoryAvailable, setAuthDirectoryAvailable] = useState(false);

  const loadUsers = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    setError(null);
    try {
      const response = await fetch("/api/admin/users", { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Unable to load users.");
      setUsers(result.users);
      setAudit(result.audit);
      setDepartments(result.departments ?? []);
      setProvisioningConfigured(result.provisioning_configured === true);
      setAuthDirectoryAvailable(result.auth_directory_available === true);
      if (!silent) {
        setEditing(
          Object.fromEntries(
            (result.users as ManagedUser[]).map((user) => [user.id, user]),
          ),
        );
      }
    } catch (loadError) {
      setError(
        loadError instanceof Error ? loadError.message : "Unable to load users.",
      );
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadUsers();
  }, [loadUsers]);

  useEffect(() => {
    const interval = window.setInterval(() => {
      void loadUsers(true);
    }, 30 * 1000);
    return () => window.clearInterval(interval);
  }, [loadUsers]);

  const filteredUsers = useMemo(() => {
    const term = search.trim().toLowerCase();
    return users
      .filter((user) => {
        const matchesSearch =
          !term ||
          user.display_name.toLowerCase().includes(term) ||
          user.email?.toLowerCase().includes(term);
        const matchesRole = roleFilter === "all" || user.role === roleFilter;
        const matchesPresence =
          presenceFilter === "all" ||
          user.presence_status === presenceFilter;
        const status = user.deleted_at
          ? "archived"
          : user.is_active
            ? "active"
            : "inactive";
        return (
          matchesSearch &&
          matchesRole &&
          matchesPresence &&
          (statusFilter === "all" || statusFilter === status)
        );
      })
      .sort((first, second) => {
        if (sortOrder === "name") {
          return first.display_name.localeCompare(second.display_name);
        }
        const firstActivity = first.last_active_at
          ? Date.parse(first.last_active_at)
          : 0;
        const secondActivity = second.last_active_at
          ? Date.parse(second.last_active_at)
          : 0;
        return secondActivity - firstActivity;
      });
  }, [
    presenceFilter,
    roleFilter,
    search,
    sortOrder,
    statusFilter,
    users,
  ]);


  function updateDraft(
    userId: string,
    field: keyof ManagedUser,
    value: string | boolean,
  ) {
    setEditing((current) => ({
      ...current,
      [userId]: { ...current[userId], [field]: value },
    }));
  }

  async function saveUser(userId: string) {
    const draft = editing[userId];
    if (!draft) return;
    setSubmitting(true);
    setError(null);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/users/${userId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(draft),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Update failed.");
      setMessage(`${draft.display_name} was updated.`);
      await loadUsers();
    } catch (updateError) {
      setError(
        updateError instanceof Error ? updateError.message : "Update failed.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  async function archiveUser(user: ManagedUser) {
    const action = "archive";
    const warning = `Archive ${user.display_name}? The account will be deactivated and blocked from new assignments.`;
    if (!window.confirm(warning)) return;

    const confirmation = window.prompt(
      `Type "${user.email ?? user.display_name}" to ${action} this user.`,
    );
    if (confirmation === null) return;

    setSubmitting(true);
    setError(null);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/users/${user.id}`, {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ confirmation }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? `${action} failed.`);
      setMessage(`${user.display_name} was archived.`);
      await loadUsers();
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : `${action} failed.`,
      );
    } finally {
      setSubmitting(false);
    }
  }

  async function permanentlyDeleteUser(user: ManagedUser) {
    const warning = `Permanently delete ${user.display_name} from Supabase Auth? This cannot be undone and is available only when retained operational records do not prevent profile removal. Archive is the normal account-retention action.`;
    if (!window.confirm(warning)) return;
    const confirmation = window.prompt(
      `Type "${user.email ?? user.display_name}" to permanently delete this user.`,
    );
    if (confirmation === null) return;

    setSubmitting(true);
    setError(null);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/users/${user.id}`, {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ permanent: true, confirmation }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Permanent deletion failed.");
      setMessage(`${user.display_name} was permanently deleted from Auth.`);
      await loadUsers();
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "Permanent deletion failed.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  const inputClass =
    "w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-200";

  return (
    <>
      {!loading && !provisioningConfigured && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
          The profile directory remains available, but privileged Auth and
          mutation operations are not configured for this deployment. Ask the deployment
          Administrator to configure privileged server access.
        </div>
      )}
      {(message || error) && (
        <div
          role={error ? "alert" : "status"}
          className={`rounded-lg border p-4 text-sm ${
            error
              ? "border-red-200 bg-red-50 text-red-800"
              : "border-green-200 bg-green-50 text-green-800"
          }`}
        >
          {error ?? message}
        </div>
      )}

      <section className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <div className="grid gap-3 border-b border-slate-200 p-4 sm:grid-cols-2 lg:grid-cols-5">
          <input
            type="search"
            aria-label="Search users by name or email"
            placeholder="Search name or email"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            className={inputClass}
          />
          <select
            aria-label="Filter users by role"
            value={roleFilter}
            onChange={(event) => setRoleFilter(event.target.value)}
            className={inputClass}
          >
            <option value="all">All roles</option>
            {ROLES.map((role) => (
              <option key={role} value={role}>
                {role === "initiator"
                  ? "Initiator / requester"
                  : role[0].toUpperCase() + role.slice(1)}
              </option>
            ))}
          </select>
          <select
            aria-label="Filter users by status"
            value={statusFilter}
            onChange={(event) => setStatusFilter(event.target.value)}
            className={inputClass}
          >
            <option value="all">All statuses</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
            <option value="archived">Archived</option>
          </select>
          <select
            aria-label="Filter users by presence"
            value={presenceFilter}
            onChange={(event) => setPresenceFilter(event.target.value)}
            className={inputClass}
          >
            <option value="all">All recorded activity</option>
            <option value="online">Recent activity</option>
            <option value="idle">Aging activity</option>
            <option value="offline">No recent activity</option>
          </select>
          <select
            aria-label="Sort users"
            value={sortOrder}
            onChange={(event) => setSortOrder(event.target.value)}
            className={inputClass}
          >
            <option value="last_activity">Last activity</option>
            <option value="name">Display name</option>
          </select>
        </div>

        {loading ? (
          <p className="p-8 text-center text-sm text-slate-500">
            Loading users…
          </p>
        ) : filteredUsers.length === 0 ? (
          <p className="p-8 text-center text-sm text-slate-500">
            No users match the current search and filters.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-[1380px] w-full text-left text-sm">
              <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-3 py-3">Display name / Email</th>
                  <th className="px-3 py-3">Role</th>
                  <th className="px-3 py-3">Department</th>
                  <th className="px-3 py-3">Trade/discipline</th>
                  <th className="px-3 py-3">Status</th>
                  <th className="px-3 py-3">Recorded activity</th>
                  <th className="px-3 py-3">Activity / Sign-in</th>
                  <th className="px-3 py-3">Created</th>
                  <th className="px-3 py-3">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredUsers.map((user) => {
                  const draft = editing[user.id] ?? user;
                  const isCurrent = user.id === currentUserId;
                  const userAudit = audit.filter((entry) =>
                    auditTargetsUser(entry, user.id),
                  );

                  return (
                    <Fragment key={user.id}>
                      <tr className="align-top">
                        <td className="space-y-2 px-3 py-4">
                          <input
                            aria-label={`Display name for ${user.email}`}
                            value={draft.display_name}
                            onChange={(event) =>
                              updateDraft(
                                user.id,
                                "display_name",
                                event.target.value,
                              )
                            }
                            className={inputClass}
                          />
                          <div className="break-all text-xs text-slate-500">
                            {user.email ?? "No email"}
                            {isCurrent && (
                              <span className="ml-2 font-semibold text-blue-700">
                                Current account
                              </span>
                            )}
                          </div>
                        </td>
                        <td className="px-3 py-4">
                          <select
                            aria-label={`Role for ${user.display_name}`}
                            value={draft.role}
                            onChange={(event) =>
                              updateDraft(
                                user.id,
                                "role",
                                event.target.value,
                              )
                            }
                            disabled={isCurrent}
                            className={inputClass}
                          >
                            {ROLES.map((role) => (
                              <option key={role} value={role}>
                                {role === "initiator"
                                  ? "Initiator / requester"
                                  : role}
                              </option>
                            ))}
                          </select>
                        </td>
                        <td className="px-3 py-4">
                          <select
                            aria-label={`Department for ${user.display_name}`}
                            value={draft.department_id ?? ""}
                            onChange={(event) =>
                              updateDraft(
                                user.id,
                                "department_id",
                                event.target.value,
                              )
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
                        </td>
                        <td className="space-y-2 px-3 py-4">
                          <input
                            aria-label={`Trade for ${user.display_name}`}
                            value={draft.trade_discipline ?? ""}
                            disabled={draft.role !== "technician"}
                            onChange={(event) =>
                              updateDraft(
                                user.id,
                                "trade_discipline",
                                event.target.value,
                              )
                            }
                            className={inputClass}
                          />
                          <input
                            aria-label={`Contact number for ${user.display_name}`}
                            value={draft.contact_number ?? ""}
                            placeholder="Contact number"
                            onChange={(event) =>
                              updateDraft(
                                user.id,
                                "contact_number",
                                event.target.value,
                              )
                            }
                            className={inputClass}
                          />
                        </td>
                        <td className="px-3 py-4">
                          <label className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              checked={draft.is_active}
                              disabled={isCurrent}
                              onChange={(event) =>
                                updateDraft(
                                  user.id,
                                  "is_active",
                                  event.target.checked,
                                )
                              }
                              className="h-4 w-4 rounded border-slate-300 text-blue-600"
                            />
                            <span>
                              {user.deleted_at
                                ? "Archived"
                                : draft.is_active
                                  ? "Active"
                                  : "Inactive"}
                            </span>
                          </label>
                          {authDirectoryAvailable && !user.email_confirmed_at && (
                            <p className="mt-1 text-xs text-amber-700">
                              Pending activation
                            </p>
                          )}
                          {user.password_change_required && (
                            <p className="mt-1 text-xs font-semibold text-blue-700">
                              First password change required
                            </p>
                          )}
                        </td>
                        <td className="px-3 py-4">
                          <span
                            className={`inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${
                              user.presence_status === "online"
                                ? "bg-green-100 text-green-800"
                                : user.presence_status === "idle"
                                  ? "bg-amber-100 text-amber-800"
                                  : "bg-slate-100 text-slate-600"
                            }`}
                          >
                            {user.presence_status === "online"
                              ? "Recent activity"
                              : user.presence_status === "idle"
                                ? "Aging activity"
                                : "No recent activity"}
                          </span>
                          <p className="mt-2 max-w-44 text-xs text-slate-500">
                            {user.session_status}
                          </p>
                          {user.last_seen_route && (
                            <p
                              className="mt-1 max-w-44 truncate text-xs text-slate-400"
                              title={user.last_seen_route}
                            >
                              Area: {user.last_seen_route}
                            </p>
                          )}
                        </td>
                        <td className="px-3 py-4 text-xs text-slate-500">
                          <p>Last active: {formatDate(user.last_active_at)}</p>
                          <p className="mt-1">
                            Last sign-in:{" "}
                            {authDirectoryAvailable
                              ? formatDate(user.last_sign_in_at)
                              : "Auth directory unavailable"}
                          </p>
                        </td>
                        <td className="px-3 py-4 text-xs text-slate-500">
                          {formatDate(user.created_at)}
                        </td>
                        <td className="space-y-2 px-3 py-4">
                          <button
                            type="button"
                            disabled={submitting || !provisioningConfigured}
                            onClick={() => void saveUser(user.id)}
                            className="block w-full rounded-md bg-blue-600 px-3 py-2 text-xs font-semibold text-white hover:bg-blue-700 disabled:opacity-50"
                          >
                            Save
                          </button>
                          <button
                            type="button"
                            onClick={() =>
                              setActivityUserId(
                                activityUserId === user.id ? null : user.id,
                              )
                            }
                            className="block w-full rounded-md border border-slate-300 px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50"
                          >
                            Activity ({userAudit.length})
                          </button>
                          {!isCurrent && (
                            <>
                              <button
                                type="button"
                                disabled={submitting}
                                onClick={() => void archiveUser(user)}
                                className="block w-full rounded-md border border-amber-300 px-3 py-2 text-xs font-semibold text-amber-800 hover:bg-amber-50"
                              >
                                Archive
                              </button>
                              <button
                                type="button"
                                disabled={submitting || !provisioningConfigured}
                                onClick={() => void permanentlyDeleteUser(user)}
                                className="block w-full rounded-md border border-red-300 px-3 py-2 text-xs font-semibold text-red-700 hover:bg-red-50 disabled:opacity-50"
                                title="Requires privileged Auth access and no blocking retained references"
                              >
                                Permanent delete
                              </button>
                            </>
                          )}
                        </td>
                      </tr>
                      {activityUserId === user.id && (
                        <tr>
                          <td colSpan={9} className="bg-slate-50 px-5 py-4">
                            <h3 className="font-semibold text-slate-900">
                              Administrative activity
                            </h3>
                            {userAudit.length === 0 ? (
                              <p className="mt-2 text-sm text-slate-500">
                                No administrative activity recorded.
                              </p>
                            ) : (
                              <ul className="mt-2 space-y-2 text-sm text-slate-600">
                                {userAudit.map((entry) => (
                                  <li key={entry.id}>
                                    {formatDate(entry.created_at)} ·{" "}
                                    {entry.actor ?? "Administrator"} ·{" "}
                                    {operationalLabel(entry.action)}
                                  </li>
                                ))}
                              </ul>
                            )}
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}

