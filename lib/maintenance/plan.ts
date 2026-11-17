/** M34 maintenance plan: group maintenance tasks by how often they are done. */
export const PLAN_FREQUENCIES = [
  { id: "daily", label: "Daily" },
  { id: "weekly", label: "Weekly" },
  { id: "monthly", label: "Monthly" },
  { id: "quarterly", label: "Quarterly" },
  { id: "sixmonthly", label: "Six-monthly" },
  { id: "annual", label: "Annual" },
  { id: "other", label: "Other" },
] as const;
export type PlanFrequency = (typeof PLAN_FREQUENCIES)[number]["id"];

export function planFrequency(value: number, unit: string): PlanFrequency {
  const days = unit === "day" ? value : unit === "week" ? value * 7 : -1;
  if (days === 1) return "daily";
  if (days === 7) return "weekly";
  const months = unit === "month" ? value : unit === "year" ? value * 12 : -1;
  if (months === 1) return "monthly";
  if (months === 3) return "quarterly";
  if (months === 6) return "sixmonthly";
  if (months === 12) return "annual";
  return "other";
}

export type PlanDocument = { id: string; title: string; kind: string; original_filename: string };
export type PlanTask = {
  id: string; number: string; state: string; title: string; scope: string; frequency: PlanFrequency; every: string;
  assetId: string; assetTag: string; assetName: string; location: string; criticality: string; facilityId: string | null;
  technicianId: string | null; documents: PlanDocument[];
};
export type PlanTechnician = { id: string; display_name: string; trade_discipline: string | null };
