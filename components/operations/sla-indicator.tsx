"use client";
import { useEffect, useMemo, useState } from "react";
import { incidentSla } from "@/lib/incidents/sla";

function duration(seconds: number) {
  const minutes = Math.floor(seconds / 60); const remainder = seconds % 60;
  return `${minutes}:${String(remainder).padStart(2, "0")}`;
}

export function SlaIndicator({ reportedAt, deadline, acknowledgedAt, compact = false }: { reportedAt: string; deadline: string; acknowledgedAt: string | null; compact?: boolean }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => { if (acknowledgedAt) return; const timer = window.setInterval(() => setNow(new Date()), 1000); return () => window.clearInterval(timer); }, [acknowledgedAt]);
  const sla = useMemo(() => incidentSla(reportedAt, deadline, acknowledgedAt, now), [reportedAt, deadline, acknowledgedAt, now]);
  const text = sla.acknowledged ? `Acknowledged in ${duration(sla.elapsed_seconds)}` : sla.acknowledgement_overdue ? `Overdue by ${duration(Math.max(0, Math.floor((now.getTime() - new Date(deadline).getTime()) / 1000)))}` : `${duration(sla.time_remaining_seconds)} to acknowledge`;
  return <div aria-live="polite" className={`${compact ? "text-xs" : "text-sm"} font-bold ${sla.escalation_required ? "text-red-800" : sla.acknowledged ? "text-emerald-700" : "text-amber-800"}`}><span>{text}</span>{sla.escalation_required && <span className="ml-2 rounded bg-red-700 px-2 py-0.5 text-white">Escalation required</span>}</div>;
}
