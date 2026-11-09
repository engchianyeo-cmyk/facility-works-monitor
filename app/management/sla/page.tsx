import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentIdentity } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { loadManagementMetrics } from "@/lib/reports/load-metrics";
import { compliancePercent } from "@/lib/reports/management";
import { SlaDocumentForm } from "@/components/sla/document-form";
import { DocumentActions } from "@/components/sla/document-actions";
import { ProposalActions } from "@/components/sla/proposal-actions";

/** D-45 (9 Nov 2026): the text read from a document, without the technical wrapper the reader adds around it. */
function plainExcerpt(value: string | null) {
  return (value ?? "").replace(/<\/?DOCUMENT_CONTENT>/g, "").replace(/\s+/g, " ").trim();
}

const STATE: Record<string, string> = { pending: "Not checked yet", approved: "Approved", rejected: "Rejected", modified: "Approved with changes" };

export default async function Page() {
  const i = await getCurrentIdentity();
  if (!i) redirect("/login?next=/management/sla");
  if (!["approver", "supervisor", "administrator"].includes(i.role)) redirect("/");
  const s = await createClient();
  const [m, d, p, v] = await Promise.all([
    loadManagementMetrics(s),
    s.from("sla_documents").select("id,title,agreement_reference,version_label,maintenance_model,review_status,approval_status,original_filename,uploaded_at").order("uploaded_at", { ascending: false }),
    s.from("sla_extraction_proposals").select("id,document_id,source_page,source_section,source_clause,source_excerpt,extracted_obligation,proposed_rule,confidence,ambiguity_warning,human_approval_state,approved_rule_id").order("created_at", { ascending: false }),
    s.from("sla_agreement_versions").select("id,version_number").in("approval_status", ["draft", "pending_approval"]).order("version_number"),
  ]);
  const versions = v.data ?? [];
  const compliance = compliancePercent(m);
  const tiles: Array<[string, string | number, string]> = [
    ["SLA compliance", compliance === null ? "No data yet" : `${compliance}%`, "Share of Work Orders fixed within their SLA time"],
    ["At risk", m.atRisk, "Open Work Orders that have used 75% of their time"],
    ["Breached", m.breached, "Open Work Orders past their SLA time"],
    ["Open escalations", m.openEscalations, "Alerts sent to managers and not yet closed"],
  ];
  return (
    <main className="mx-auto max-w-7xl space-y-6 p-6">
      <header className="flex flex-wrap justify-between gap-3">
        <div>
          <p className="text-xs font-black uppercase text-indigo-700">Managers only</p>
          <h1 className="text-3xl font-black">SLA documents and rules</h1>
          <p className="mt-1 max-w-3xl text-slate-600">Turn the service agreement into the times the app tracks. The app reads the document and suggests clauses; nothing is used until a manager checks and approves it. Approved times appear for everyone on the <Link href="/sla" className="font-semibold text-blue-700 underline">Site SLA</Link> page and as a countdown on each Work Order.</p>
        </div>
        <div className="flex gap-2">
          <Link href="/sla" className="rounded border px-4 py-3 font-bold">Site SLA</Link>
          <Link href="/management/staffing" className="rounded border px-4 py-3 font-bold">Staffing</Link>
          <Link href="/management/reports" className="rounded bg-indigo-700 px-4 py-3 font-bold text-white">Reports</Link>
        </div>
      </header>
      <section className="grid gap-3 sm:grid-cols-4">
        {tiles.map(([label, value, help]) => <div key={label} className="rounded-xl border bg-white p-4"><p className="font-semibold">{label}</p><strong className="text-2xl">{value}</strong><p className="mt-1 text-xs text-slate-500">{help}</p></div>)}
      </section>
      <section aria-labelledby="sla-step-1" className="space-y-2">
        <h2 id="sla-step-1" className="text-xl font-black">1. Add a service agreement</h2>
        <p className="text-sm text-slate-600">Enter the agreement details and attach the document (PDF or Word). In this test version nothing is sent to an outside AI service.</p>
        <SlaDocumentForm />
      </section>
      <section className="grid gap-5 lg:grid-cols-2">
        <div className="rounded-xl border bg-white p-5">
          <h2 className="text-xl font-black">2. Agreements on file</h2>
          <p className="text-sm text-slate-600">Read each document to find its SLA clauses. The current reader is a simple pattern reader for testing, not real AI.</p>
          {(d.data ?? []).length === 0 && <p className="mt-3 text-sm text-slate-500">No agreements yet.</p>}
          {(d.data ?? []).map((x) => <article key={x.id} className="my-3 rounded bg-slate-50 p-3">
            <strong>{x.title}{x.version_label ? ` — ${x.version_label}` : ""}</strong>
            <p className="text-sm">{x.agreement_reference} · {String(x.maintenance_model ?? "").replace("_", "-").toLowerCase()} · {x.original_filename}</p>
            <p className="text-sm text-slate-600">Reading: {String(x.review_status ?? "").toLowerCase()} · Approval: {String(x.approval_status ?? "").toLowerCase()}</p>
            <DocumentActions id={x.id} />
          </article>)}
        </div>
        <div className="rounded-xl border bg-white p-5">
          <h2 className="text-xl font-black">3. Check each clause found</h2>
          <p className="text-sm text-slate-600">Compare the suggestion with the document text, correct the minutes if needed, then approve or reject. Only approved clauses become SLA rules.</p>
          {(p.data ?? []).length === 0 && <p className="mt-3 text-sm text-slate-500">No clauses found yet. Read a document first.</p>}
          {(p.data ?? []).map((x) => {
            const excerpt = plainExcerpt(x.source_excerpt);
            const obligation = plainExcerpt(x.extracted_obligation);
            return <article key={x.id} className="my-3 rounded bg-slate-50 p-3">
              <strong>Clause {x.source_clause ?? "(not numbered)"}</strong> <span className="text-sm text-slate-600">· reader&apos;s confidence {Math.round(Number(x.confidence ?? 0) * 100)}% · {STATE[x.human_approval_state] ?? x.human_approval_state}{x.approved_rule_id ? " · in use as an SLA rule" : ""}</span>
              <p className="mt-1 text-xs text-slate-500">From: {x.source_page ?? x.source_section ?? "the document"}</p>
              <blockquote className="my-2 border-l-4 pl-2 text-sm">{excerpt || "No text captured."}</blockquote>
              {obligation && obligation !== excerpt && <p className="text-sm"><b>Suggested obligation:</b> {obligation}</p>}
              {x.ambiguity_warning && <p className="text-sm text-amber-700">Check: {x.ambiguity_warning}</p>}
              <ProposalActions id={x.id} reviewState={x.human_approval_state} versions={versions} />
            </article>;
          })}
        </div>
      </section>
    </main>
  );
}
