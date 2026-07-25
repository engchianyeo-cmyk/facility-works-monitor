import fs from 'fs';
import path from 'path';

type Row = {
  workOrderNo: string;
  title: string;
  description: string;
  floorBuilding: string;
  location: string;
  category: string;
  priority: string;
  status: string;
};

function parseCSV(content: string): string[][] {
  const rows: string[][] = [];
  let cur = '';
  let row: string[] = [];
  let inQuotes = false;
  for (let i = 0; i < content.length; i++) {
    const ch = content[i];
    if (ch === '"') {
      if (inQuotes && content[i + 1] === '"') {
        cur += '"';
        i++; // skip escaped quote
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch === ',' && !inQuotes) {
      row.push(cur);
      cur = '';
    } else if ((ch === '\n' || ch === '\r') && !inQuotes) {
      // handle CRLF and LF
      if (cur !== '' || row.length > 0) {
        row.push(cur);
        rows.push(row.map((c) => c.trim()));
      }
      cur = '';
      row = [];
      // skip following LF for CRLF
      if (ch === '\r' && content[i + 1] === '\n') i++;
    } else {
      cur += ch;
    }
  }
  if (cur !== '' || row.length > 0) {
    row.push(cur);
    rows.push(row.map((c) => c.trim()));
  }
  return rows;
}

function readSeedCategories(): string[] {
  const seedPath = path.join(__dirname, '..', 'supabase', 'seeds', 'categories.sql');
  if (!fs.existsSync(seedPath)) return [];
  const content = fs.readFileSync(seedPath, 'utf8');
  const matches = content.match(/\('([^']+)'\)/g);
  if (!matches) return [];
  return matches.map((m) => m.replace(/[^\w\s\-\/\.]/g, '').trim());
}

function normalizePriority(p: string): string {
  const v = p.trim().toLowerCase();
  if (v === 'low') return 'low';
  if (v === 'medium' || v === 'med') return 'medium';
  if (v === 'high') return 'high';
  if (v === 'critical' || v === 'urgent') return 'critical';
  return 'medium';
}

function normalizeStatus(s: string): string {
  const v = s.trim().toLowerCase();
  if (v === 'submitted') return 'submitted';
  if (v === 'approved') return 'approved';
  if (v === 'in progress' || v === 'in_progress' || v === 'inprogress') return 'in_progress';
  if (v === 'done' || v === 'completed') return 'done';
  if (v === 'rejected') return 'rejected';
  return 'submitted';
}

function buildLocation(floorBuilding: string, location: string) {
  const fb = floorBuilding.trim();
  const loc = location.trim();
  if (!fb) return loc || 'Unknown location';
  if (!loc) return fb;
  return `${fb} – ${loc}`;
}

function headerIndex(headers: string[], name: string) {
  const idx = headers.findIndex((h) => h.trim().toLowerCase() === name.toLowerCase());
  return idx;
}

async function main() {
  const csvPath = path.join(__dirname, '..', 'data', 'FM_Works_15_Work_Orders.csv');
  if (!fs.existsSync(csvPath)) {
    console.error('CSV file not found at', csvPath);
    process.exitCode = 2;
    return;
  }

  const raw = fs.readFileSync(csvPath, 'utf8');
  const rows = parseCSV(raw);
  if (rows.length === 0) {
    console.error('CSV appears empty');
    process.exitCode = 2;
    return;
  }

  const headers = rows[0].map((h) => h.trim());
  const data = rows.slice(1).map((r) => {
    return {
      workOrderNo: r[headerIndex(headers, 'Work Order No.')],
      title: r[headerIndex(headers, 'Title')] || r[headerIndex(headers, 'Work Order No.')] || '',
      description: r[headerIndex(headers, 'Description')] || '',
      floorBuilding: r[headerIndex(headers, 'Floor / Building')] || '',
      location: r[headerIndex(headers, 'Location')] || '',
      category: r[headerIndex(headers, 'Category')] || '',
      priority: r[headerIndex(headers, 'Priority')] || '',
      status: r[headerIndex(headers, 'Status')] || '',
    } as Row;
  });

  console.log(`Read ${data.length} data rows (excluding header).`);

  const seedCategories = readSeedCategories();
  console.log('Existing seed categories (from supabase/seeds/categories.sql):');
  console.log(seedCategories.join(', '));

  const uniqueCsvCategories = Array.from(new Set(data.map((d) => d.category.trim()).filter(Boolean)));
  console.log('Unique CSV categories:');
  console.log(uniqueCsvCategories.join(', ') || '(none)');

  const mapping: Record<string, { match?: string; reason?: string }> = {};
  uniqueCsvCategories.forEach((cat) => {
    const lower = cat.toLowerCase();
    const match = seedCategories.find((sc) => sc.toLowerCase() === lower || sc.toLowerCase().includes(lower) || lower.includes(sc.toLowerCase()));
    if (match) mapping[cat] = { match };
    else mapping[cat] = { reason: 'No exact or obvious match; requires decision' };
  });

  console.log('Proposed category mapping (CSV -> existing):');
  console.log(mapping);

  const preview = data.map((d) => {
    return {
      workOrderNo: d.workOrderNo,
      title: d.title,
      description: d.description,
      location: buildLocation(d.floorBuilding, d.location),
      category: d.category,
      mappedCategory: mapping[d.category]?.match ?? null,
      priority: normalizePriority(d.priority),
      status: normalizeStatus(d.status),
      submitted_by: 'Practitioner Preview Data',
      contact_number: null,
    };
  });

  console.log('DRY-RUN preview of normalized records:');
  console.log(JSON.stringify(preview, null, 2));

  console.log('\nSummary:');
  const priorities = Array.from(new Set(preview.map((p) => p.priority))).join(', ');
  const statuses = Array.from(new Set(preview.map((p) => p.status))).join(', ');
  console.log(`Priorities seen: ${priorities}`);
  console.log(`Statuses seen: ${statuses}`);

  console.log('\nDuplicate detection (exact title + location):');
  const seen = new Set<string>();
  const duplicates: any[] = [];
  preview.forEach((p) => {
    const key = `${p.title.toLowerCase()}|${p.location.toLowerCase()}`;
    if (seen.has(key)) duplicates.push(p);
    seen.add(key);
  });
  console.log(`Exact duplicates detected: ${duplicates.length}`);
  if (duplicates.length) console.log(JSON.stringify(duplicates, null, 2));

  console.log('\nDRY-RUN complete. To perform actual import, rerun with --apply (not implemented in DRY-RUN).');
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
