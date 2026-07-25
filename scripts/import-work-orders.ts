import fs from "fs";
import path from "path";
import { loadEnvConfig } from "@next/env";
import { createClient } from "@supabase/supabase-js";

const CSV_FILENAME = "FM_Works_15_Work_Orders.csv";
const SUBMITTED_BY = "FM Works Test Data";

const REQUIRED_HEADERS = [
  "Work Order No.",
  "Title",
  "Description",
  "Floor / Building",
  "Location",
  "Category",
  "Priority",
  "Status",
] as const;

const CATEGORY_MAPPING: Readonly<Record<string, string>> = {
  Electrical: "Electrical",
  Lift: "Lift",
  "Fire Protection": "Fire Protection",
  "HVAC / Plumbing": "Plumbing",
  HVAC: "HVAC",
  "Access Control": "Security",
  "Building / Roofing": "Structural",
  Plumbing: "Plumbing",
  "Security / Access": "Security",
  Flooring: "Flooring",
  "General Facilities": "General Maintenance",
  Painting: "Painting",
  Cleaning: "Cleaning",
};

const PRIORITY_MAPPING: Readonly<Record<string, string>> = {
  Low: "low",
  Medium: "medium",
  High: "high",
  Critical: "critical",
};

const STATUS_MAPPING: Readonly<Record<string, string>> = {
  Submitted: "submitted",
  Approved: "approved",
  "In Progress": "in_progress",
  Done: "done",
  Rejected: "rejected",
};

type CsvRow = {
  workOrderNo: string;
  title: string;
  description: string;
  floorBuilding: string;
  location: string;
  category: string;
  priority: string;
  status: string;
};

type PreparedRow = {
  workOrderNo: string;
  title: string;
  description: string;
  location: string;
  categoryId: string;
  csvCategory: string;
  mappedCategory: string;
  priority: string;
  status: string;
  duplicate: boolean;
};

type ValidationIssue = {
  workOrderNo: string;
  reasons: string[];
};

function parseCsv(content: string): string[][] {
  const rows: string[][] = [];
  let field = "";
  let row: string[] = [];
  let inQuotes = false;

  for (let index = 0; index < content.length; index += 1) {
    const character = content[index];
    if (character === '"') {
      if (inQuotes && content[index + 1] === '"') {
        field += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (character === "," && !inQuotes) {
      row.push(field);
      field = "";
    } else if ((character === "\n" || character === "\r") && !inQuotes) {
      if (field !== "" || row.length > 0) {
        row.push(field);
        rows.push(row.map((value) => value.trim()));
      }
      field = "";
      row = [];
      if (character === "\r" && content[index + 1] === "\n") index += 1;
    } else {
      field += character;
    }
  }

  if (inQuotes) throw new Error("CSV contains an unterminated quoted field.");
  if (field !== "" || row.length > 0) {
    row.push(field);
    rows.push(row.map((value) => value.trim()));
  }
  return rows;
}

function buildLocation(floorBuilding: string, location: string): string {
  const floor = floorBuilding.trim();
  const place = location.trim();
  if (floor && place) return `${floor} - ${place}`;
  return floor || place;
}

function comparisonKey(title: string, location: string): string {
  const normalize = (value: string) =>
    value.trim().replace(/\s+/g, " ").toLocaleLowerCase("en-US");
  return `${normalize(title)}\u0000${normalize(location)}`;
}

function printSummary(values: {
  csvRows: number;
  validRows: number;
  imported: number;
  skippedDuplicates: number;
  failed: number;
}): void {
  console.log("\nSummary:");
  console.log(`CSV rows: ${values.csvRows}`);
  console.log(`Valid rows: ${values.validRows}`);
  console.log(`Imported: ${values.imported}`);
  console.log(`Skipped duplicates: ${values.skippedDuplicates}`);
  console.log(`Failed: ${values.failed}`);
}

async function main(): Promise<void> {
  const apply = process.argv.slice(2).includes("--apply");
  const unknownArguments = process.argv
    .slice(2)
    .filter((argument) => argument !== "--apply");
  if (unknownArguments.length > 0) {
    throw new Error(`Unknown argument(s): ${unknownArguments.join(", ")}`);
  }

  const projectRoot = path.resolve(__dirname, "..");
  const csvPath = path.join(projectRoot, "data", CSV_FILENAME);
  if (!fs.existsSync(csvPath)) throw new Error(`CSV file not found: ${csvPath}`);

  const parsed = parseCsv(fs.readFileSync(csvPath, "utf8"));
  if (parsed.length === 0) throw new Error("CSV appears empty.");

  const headers = parsed[0].map((header) => header.replace(/^\uFEFF/, "").trim());
  const missingHeaders = REQUIRED_HEADERS.filter(
    (required) => !headers.some((header) => header === required),
  );
  if (missingHeaders.length > 0) {
    throw new Error(`Missing required CSV header(s): ${missingHeaders.join(", ")}`);
  }

  const indexOf = (header: (typeof REQUIRED_HEADERS)[number]) =>
    headers.indexOf(header);
  const csvRows: CsvRow[] = parsed.slice(1).map((values) => ({
    workOrderNo: values[indexOf("Work Order No.")]?.trim() ?? "",
    title: values[indexOf("Title")]?.trim() ?? "",
    description: values[indexOf("Description")]?.trim() ?? "",
    floorBuilding: values[indexOf("Floor / Building")]?.trim() ?? "",
    location: values[indexOf("Location")]?.trim() ?? "",
    category: values[indexOf("Category")]?.trim() ?? "",
    priority: values[indexOf("Priority")]?.trim() ?? "",
    status: values[indexOf("Status")]?.trim() ?? "",
  }));

  console.log(apply ? "Mode: APPLY" : "Mode: DRY-RUN (zero database writes)");
  console.log(`Read ${csvRows.length} CSV rows.`);

  loadEnvConfig(projectRoot);
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are required.",
    );
  }
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: liveCategories, error: categoryError } = await supabase
    .from("categories")
    .select("id, name")
    .order("name");
  if (categoryError) {
    throw new Error(`Unable to fetch live categories: ${categoryError.message}`);
  }
  const categoriesByName = new Map(
    (liveCategories ?? []).map((category) => [category.name, category.id]),
  );

  console.log("\nResolved category mappings (CSV -> live category):");
  for (const csvCategory of [...new Set(csvRows.map((row) => row.category))]) {
    const mapped = CATEGORY_MAPPING[csvCategory];
    const id = mapped ? categoriesByName.get(mapped) : undefined;
    console.log(
      `${csvCategory || "(empty)"} -> ${mapped ?? "UNMAPPED"}${id ? ` (${id})` : " (NOT FOUND)"}`,
    );
  }

  const issues: ValidationIssue[] = [];
  const candidates: Omit<PreparedRow, "duplicate">[] = [];
  csvRows.forEach((row, rowIndex) => {
    const reasons: string[] = [];
    const displayNumber = row.workOrderNo || `row ${rowIndex + 2}`;
    const combinedLocation = buildLocation(row.floorBuilding, row.location);
    const mappedCategory = CATEGORY_MAPPING[row.category];
    const categoryId = mappedCategory
      ? categoriesByName.get(mappedCategory)
      : undefined;
    const priority = PRIORITY_MAPPING[row.priority];
    const status = STATUS_MAPPING[row.status];

    if (!row.workOrderNo) reasons.push("missing Work Order No.");
    if (!row.title) reasons.push("missing title");
    if (!combinedLocation) reasons.push("missing location");
    if (!priority) reasons.push(`invalid priority: ${row.priority || "(empty)"}`);
    if (!status) reasons.push(`invalid status: ${row.status || "(empty)"}`);
    if (!row.category) reasons.push("empty category");
    else if (!mappedCategory)
      reasons.push(`unresolved category mapping: ${row.category}`);
    else if (!categoryId)
      reasons.push(`mapped category not found in live categories: ${mappedCategory}`);

    if (reasons.length > 0) {
      issues.push({ workOrderNo: displayNumber, reasons });
      return;
    }
    candidates.push({
      workOrderNo: row.workOrderNo,
      title: row.title,
      description: row.description,
      location: combinedLocation,
      categoryId: categoryId!,
      csvCategory: row.category,
      mappedCategory,
      priority,
      status,
    });
  });

  const { data: existingOrders, error: duplicateError } = await supabase
    .from("work_orders")
    .select("title, location");
  if (duplicateError) {
    throw new Error(
      `Unable to check live work order duplicates: ${duplicateError.message}`,
    );
  }
  const existingKeys = new Set(
    (existingOrders ?? []).map((order) =>
      comparisonKey(order.title ?? "", order.location ?? ""),
    ),
  );
  const prepared: PreparedRow[] = candidates.map((row) => ({
    ...row,
    duplicate: existingKeys.has(comparisonKey(row.title, row.location)),
  }));
  const duplicateCount = prepared.filter((row) => row.duplicate).length;

  console.log("\nValidation results:");
  if (issues.length === 0) console.log(`PASS: all ${csvRows.length} rows are valid.`);
  else {
    for (const issue of issues) {
      console.error(`INVALID: ${issue.workOrderNo} - ${issue.reasons.join("; ")}`);
    }
  }

  console.log("\nDuplicate results:");
  if (duplicateCount === 0) console.log("No duplicates found in the live database.");
  for (const row of prepared.filter((item) => item.duplicate)) {
    console.log(`SKIPPED DUPLICATE: ${row.workOrderNo} - ${row.title}`);
  }

  console.log("\nPreview:");
  for (const row of prepared) {
    console.log(
      `${row.duplicate ? "SKIPPED DUPLICATE" : "READY"}: ${row.workOrderNo} - ${row.title}`,
    );
    console.log(
      `  location=${row.location}; category=${row.mappedCategory}; priority=${row.priority}; status=${row.status}; submitted_by=${SUBMITTED_BY}`,
    );
  }

  if (issues.length > 0) {
    console.error("\nValidation failed. No rows were inserted.");
    printSummary({
      csvRows: csvRows.length,
      validRows: candidates.length,
      imported: 0,
      skippedDuplicates: duplicateCount,
      failed: issues.length,
    });
    process.exitCode = 1;
    return;
  }

  if (!apply) {
    console.log("\nDRY-RUN complete. No database writes were performed.");
    console.log(
      "Run with --apply only when you explicitly intend to insert non-duplicate rows.",
    );
    printSummary({
      csvRows: csvRows.length,
      validRows: prepared.length,
      imported: 0,
      skippedDuplicates: duplicateCount,
      failed: 0,
    });
    return;
  }

  let imported = 0;
  for (const row of prepared) {
    if (row.duplicate) {
      console.log(`SKIPPED DUPLICATE: ${row.workOrderNo} - ${row.title}`);
      continue;
    }
    const { error } = await supabase.from("work_orders").insert({
      title: row.title,
      description: row.description || null,
      location: row.location,
      category_id: row.categoryId,
      priority: row.priority,
      status: row.status,
      submitted_by: SUBMITTED_BY,
    });
    if (error) {
      console.error(`IMPORT FAILED: ${row.workOrderNo} - ${row.title}`);
      console.error(error);
      printSummary({
        csvRows: csvRows.length,
        validRows: prepared.length,
        imported,
        skippedDuplicates: duplicateCount,
        failed: 1,
      });
      process.exitCode = 1;
      return;
    }
    imported += 1;
    console.log(`IMPORTED: ${row.workOrderNo} - ${row.title}`);
  }

  printSummary({
    csvRows: csvRows.length,
    validRows: prepared.length,
    imported,
    skippedDuplicates: duplicateCount,
    failed: 0,
  });
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
