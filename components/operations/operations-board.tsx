import type { ReactNode } from "react";

export function OperationsBoard({ children, empty }: { children: ReactNode; empty?: boolean }) {
  if (empty) return <div className="rounded-2xl border border-dashed border-slate-300 bg-white p-10 text-center text-slate-600">No incidents match this operational view.</div>;
  return <ul aria-label="Live incident operations board" className="grid gap-4 lg:grid-cols-2">{children}</ul>;
}

export function OperationsCard({ children, emergency = false }: { children: ReactNode; emergency?: boolean }) {
  return <li className={`overflow-hidden rounded-2xl border-2 shadow-sm ${emergency ? "border-red-500 bg-red-50 shadow-red-100" : "border-slate-200 bg-white"}`}>{children}</li>;
}
