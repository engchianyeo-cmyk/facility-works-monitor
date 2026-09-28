export type ContractorActualCsvRow = {
  workOrderNumber: string;
  rateCode: string;
  quantity: number;
  actualUnitRate: number | null;
  workerName: string | null;
  workerId: string | null;
  workDate: string | null;
  exceptionReason: string | null;
  remarks: string | null;
};

function parseCsvMatrix(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  const source = text.replace(/^\uFEFF/, "");
  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];
    if (ch === '"') {
      if (quoted && source[i + 1] === '"') { field += '"'; i += 1; }
      else quoted = !quoted;
    } else if (ch === ',' && !quoted) {
      row.push(field.trim()); field = "";
    } else if ((ch === '\n' || ch === '\r') && !quoted) {
      if (ch === '\r' && source[i + 1] === '\n') i += 1;
      row.push(field.trim()); field = "";
      if (row.some((value) => value !== "")) rows.push(row);
      row = [];
    } else field += ch;
  }
  row.push(field.trim());
  if (row.some((value) => value !== "")) rows.push(row);
  return rows;
}

function numberValue(value: string | undefined): number | null {
  if (!value?.trim()) return null;
  const n = Number(value.replace(/[$,]/g, "").trim());
  return Number.isFinite(n) ? n : null;
}

function clean(value: string | undefined) { return value?.trim() || null; }

export function parseContractorActualCsv(text: string): { rows: ContractorActualCsvRow[]; errors: string[] } {
  const matrix = parseCsvMatrix(text);
  if (matrix.length < 2) return { rows: [], errors: ["CSV must contain a header row and at least one data row."] };
  const headers = matrix[0].map((header) => header.trim().toLowerCase());
  const at = (record: string[], ...names: string[]) => {
    const index = names.map((name) => headers.indexOf(name.toLowerCase())).find((candidate) => candidate >= 0) ?? -1;
    return index >= 0 ? record[index] : undefined;
  };
  const errors: string[] = [];
  const rows: ContractorActualCsvRow[] = [];

  matrix.slice(1).forEach((record, index) => {
    const rowNo = index + 2;
    const workOrderNumber = clean(at(record, "Work Order No.", "Work Order No", "Work Order"));
    const rateCode = clean(at(record, "Rate Code", "Item / Part No.", "Item / Part No", "Equipment / Service Ref"));
    if (!workOrderNumber) errors.push(`Row ${rowNo}: Work Order No. is required.`);
    if (!rateCode) errors.push(`Row ${rowNo}: Rate Code is required.`);

    const common = {
      workOrderNumber: workOrderNumber ?? "",
      rateCode: rateCode ?? "",
      workerName: clean(at(record, "Personnel Name", "Worker Name")),
      workerId: clean(at(record, "Employee / Worker ID", "Worker ID")),
      workDate: clean(at(record, "Work Date")),
      exceptionReason: clean(at(record, "Exception Reason")),
      remarks: clean(at(record, "Remarks")),
    };

    const normalHours = numberValue(at(record, "Normal Hours"));
    const otHours = numberValue(at(record, "OT Hours"));
    const publicHolidayHours = numberValue(at(record, "Public Holiday Hours"));
    const personnelShape = normalHours !== null || otHours !== null || publicHolidayHours !== null;

    if (personnelShape) {
      const normalRate = numberValue(at(record, "Normal Hourly Rate (SGD)", "Normal Hourly Rate"));
      const otRate = numberValue(at(record, "OT Hourly Rate (SGD)", "OT Hourly Rate"));
      const publicHolidayRate = numberValue(at(record, "Public Holiday Hourly Rate (SGD)", "Public Holiday Hourly Rate"));
      if (!common.workerName) errors.push(`Row ${rowNo}: Personnel Name is required for labour rows.`);
      const addLabour = (quantity: number | null, rate: number | null, label: string) => {
        if (!quantity || quantity <= 0) return;
        if (rate === null || rate < 0) { errors.push(`Row ${rowNo}: ${label} rate is invalid.`); return; }
        rows.push({ ...common, quantity, actualUnitRate: rate, exceptionReason: common.exceptionReason ?? (label === "Normal" ? null : `${label} rate submitted by contractor`) });
      };
      addLabour(normalHours, normalRate, "Normal");
      addLabour(otHours, otRate, "Overtime");
      addLabour(publicHolidayHours, publicHolidayRate, "Public holiday");
      return;
    }

    const quantity = numberValue(at(record, "Actual Quantity", "Actual Quantity / Hours", "Quantity / Hours", "Quantity"));
    const actualUnitRate = numberValue(at(record, "Actual Unit Rate (SGD)", "Actual Unit Rate", "Unit Rate (SGD)"));
    if (quantity === null || quantity <= 0) errors.push(`Row ${rowNo}: Actual Quantity / Hours must be greater than zero.`);
    if (actualUnitRate !== null && actualUnitRate < 0) errors.push(`Row ${rowNo}: Actual Unit Rate cannot be negative.`);
    if (quantity !== null && quantity > 0) rows.push({ ...common, quantity, actualUnitRate });
  });

  return { rows, errors };
}
