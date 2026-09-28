"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";

type Department = {
  id: string;
  code: string;
  name: string;
  description: string | null;
  cost_centre: string | null;
  manager_id: string | null;
  parent_department_id: string | null;
  colour_tag: string | null;
  is_active: boolean;
  deleted_at: string | null;
  active_user_count: number;
};

type Manager = { id: string; display_name: string };
type DepartmentForm = Omit<Department, "id" | "deleted_at" | "active_user_count">;

const EMPTY_FORM: DepartmentForm = {
  code: "",
  name: "",
  description: "",
  cost_centre: "",
  manager_id: "",
  parent_department_id: "",
  colour_tag: "",
  is_active: true,
};

export default function DepartmentManagement() {
  const [departments, setDepartments] = useState<Department[]>([]);
  const [managers, setManagers] = useState<Manager[]>([]);
  const [form, setForm] = useState<DepartmentForm>(EMPTY_FORM);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const loadDepartments = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch("/api/admin/departments", { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Unable to load departments.");
      setDepartments(result.departments ?? []);
      setManagers(result.managers ?? []);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Unable to load departments.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void loadDepartments(); }, [loadDepartments]);

  function beginEdit(department: Department) {
    setEditingId(department.id);
    setForm({
      code: department.code,
      name: department.name,
      description: department.description ?? "",
      cost_centre: department.cost_centre ?? "",
      manager_id: department.manager_id ?? "",
      parent_department_id: department.parent_department_id ?? "",
      colour_tag: department.colour_tag ?? "",
      is_active: department.is_active,
    });
    setMessage(null);
    setError(null);
  }

  function resetForm() {
    setEditingId(null);
    setForm(EMPTY_FORM);
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    setMessage(null);
    try {
      const response = await fetch(
        editingId ? `/api/admin/departments/${editingId}` : "/api/admin/departments",
        {
          method: editingId ? "PATCH" : "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(form),
        },
      );
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Unable to save department.");
      setMessage(editingId ? "Department updated." : "Department created.");
      resetForm();
      await loadDepartments();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "Unable to save department.");
    } finally {
      setSubmitting(false);
    }
  }

  async function archive(department: Department) {
    if (!window.confirm(`Archive ${department.name}?`)) return;
    setError(null);
    setMessage(null);
    const response = await fetch(`/api/admin/departments/${department.id}`, { method: "DELETE" });
    const result = await response.json();
    if (!response.ok) {
      setError(result.error ?? "Unable to archive department.");
      return;
    }
    setMessage("Department archived.");
    if (editingId === department.id) resetForm();
    await loadDepartments();
  }

  const inputClass = "mt-1 w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-200";
  const activeDepartments = departments.filter((department) => !department.deleted_at);

  return (
    <>
      <section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <h2 className="text-xl font-bold text-slate-900">
          {editingId ? "Edit department" : "Add department"}
        </h2>
        <form onSubmit={save} className="mt-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <label className="text-sm font-medium text-slate-700">Code
            <input required maxLength={24} pattern="[A-Za-z0-9][A-Za-z0-9_-]{0,23}" value={form.code} onChange={(event) => setForm({ ...form, code: event.target.value.toUpperCase() })} className={inputClass} />
          </label>
          <label className="text-sm font-medium text-slate-700">Name
            <input required maxLength={120} value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} className={inputClass} />
          </label>
          <label className="text-sm font-medium text-slate-700">Colour tag
            <input type="text" placeholder="#2563EB" pattern="#[0-9A-Fa-f]{6}" value={form.colour_tag ?? ""} onChange={(event) => setForm({ ...form, colour_tag: event.target.value })} className={inputClass} />
          </label>
          <label className="text-sm font-medium text-slate-700">Cost centre
            <input value={form.cost_centre ?? ""} onChange={(event) => setForm({ ...form, cost_centre: event.target.value })} className={inputClass} />
          </label>
          <label className="text-sm font-medium text-slate-700">Manager
            <select value={form.manager_id ?? ""} onChange={(event) => setForm({ ...form, manager_id: event.target.value })} className={inputClass}>
              <option value="">No manager</option>
              {managers.map((manager) => <option key={manager.id} value={manager.id}>{manager.display_name}</option>)}
            </select>
          </label>
          <label className="text-sm font-medium text-slate-700">Parent department
            <select value={form.parent_department_id ?? ""} onChange={(event) => setForm({ ...form, parent_department_id: event.target.value })} className={inputClass}>
              <option value="">No parent</option>
              {activeDepartments.filter((department) => department.id !== editingId).map((department) => <option key={department.id} value={department.id}>{department.name}</option>)}
            </select>
          </label>
          <label className="text-sm font-medium text-slate-700 sm:col-span-2 lg:col-span-3">Description
            <textarea rows={3} value={form.description ?? ""} onChange={(event) => setForm({ ...form, description: event.target.value })} className={inputClass} />
          </label>
          <label className="flex items-center gap-2 text-sm font-medium text-slate-700">
            <input type="checkbox" checked={form.is_active} onChange={(event) => setForm({ ...form, is_active: event.target.checked })} /> Active
          </label>
          <div className="flex gap-3 sm:col-span-2 lg:col-span-3">
            <button disabled={submitting} className="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:opacity-50">{submitting ? "Saving…" : editingId ? "Save changes" : "Create department"}</button>
            {editingId && <button type="button" onClick={resetForm} className="rounded-lg border border-slate-300 px-4 py-2.5 text-sm font-semibold text-slate-700 hover:bg-slate-50">Cancel</button>}
          </div>
        </form>
      </section>

      {(message || error) && <p role={error ? "alert" : "status"} className={`rounded-lg border p-4 text-sm ${error ? "border-red-200 bg-red-50 text-red-800" : "border-green-200 bg-green-50 text-green-800"}`}>{error ?? message}</p>}

      <section className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
        <div className="border-b border-slate-200 px-5 py-4"><h2 className="text-xl font-bold text-slate-900">Department directory</h2></div>
        {loading ? <p className="p-8 text-center text-sm text-slate-500">Loading departments…</p> : departments.length === 0 ? <p className="p-8 text-center text-sm text-slate-500">No departments have been created.</p> : (
          <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-slate-50 text-slate-600"><tr><th className="px-5 py-3">Department</th><th className="px-5 py-3">Parent</th><th className="px-5 py-3">Users</th><th className="px-5 py-3">Status</th><th className="px-5 py-3 text-right">Actions</th></tr></thead><tbody className="divide-y divide-slate-100">{departments.map((department) => (
            <tr key={department.id} className={department.deleted_at ? "bg-slate-50 text-slate-500" : ""}>
              <td className="px-5 py-4"><div className="flex items-center gap-3">{department.colour_tag && <span className="h-3 w-3 rounded-full" style={{ backgroundColor: department.colour_tag }} />}<div><p className="font-semibold text-slate-900">{department.name}</p><p className="text-xs text-slate-500">{department.code}{department.cost_centre ? ` · ${department.cost_centre}` : ""}</p></div></div></td>
              <td className="px-5 py-4">{departments.find((candidate) => candidate.id === department.parent_department_id)?.name ?? "—"}</td>
              <td className="px-5 py-4">{department.active_user_count}</td>
              <td className="px-5 py-4">{department.deleted_at ? "Archived" : department.is_active ? "Active" : "Inactive"}</td>
              <td className="px-5 py-4"><div className="flex justify-end gap-2"><button disabled={Boolean(department.deleted_at)} onClick={() => beginEdit(department)} className="rounded border border-slate-300 px-3 py-1.5 font-medium hover:bg-slate-50 disabled:opacity-40">Edit</button><button disabled={Boolean(department.deleted_at)} onClick={() => void archive(department)} className="rounded border border-red-300 px-3 py-1.5 font-medium text-red-700 hover:bg-red-50 disabled:opacity-40">Archive</button></div></td>
            </tr>
          ))}</tbody></table></div>
        )}
      </section>
    </>
  );
}
