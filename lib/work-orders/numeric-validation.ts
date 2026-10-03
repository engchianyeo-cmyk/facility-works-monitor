const fields = ["proposed_amount", "final_contractor_amount", "confirmed_actual_cost", "committed_amount", "paid_amount", "quantity", "unit_rate", "actual_labour_hours"];

export function invalidFinancialNumber(payload: Record<string, unknown>): string | null {
  for (const field of fields) {
    const value = payload[field];
    if (value === undefined || value === null) continue;
    if (typeof value !== "number" && (typeof value !== "string" || !value.trim())) return field;
    const number = Number(value);
    if (!Number.isFinite(number) || number < 0) return field;
  }
  return null;
}
