import { createCsv } from "@/lib/exports/csv";

export type ManagementMetrics = {
  totalWorkOrders:number; slaEligible:number; slaMet:number; atRisk:number; breached:number;
  overdue:number; criticalItems:number; averageResponseMinutes:number|null; mttrMinutes:number|null;
  repeatFailures:number; pmCompliancePercent:number|null; assetAvailabilityPercent:number|null; openEscalations:number;
  byPriority:Record<string,{total:number;met:number}>;
};

export function compliancePercent(metrics:ManagementMetrics){return metrics.slaEligible?Math.round(metrics.slaMet/metrics.slaEligible*10000)/100:null;}

export function managementReportCsv(metrics:ManagementMetrics){
  const rows:(string|number|null)[][]=Object.entries(metrics).filter((entry):entry is [string,number|null]=>typeof entry[1]!=="object").map(([metric,value])=>[metric,value]);
  return createCsv(["metric","value"],rows);
}

function escapePdf(value:string){return value.replaceAll("\\","\\\\").replaceAll("(","\\(").replaceAll(")","\\)");}
export function managementReportPdf(title:string,metrics:ManagementMetrics,commentary?:string){
  const lines=[title,`SLA compliance: ${compliancePercent(metrics)??"N/A"}%`,`Work Orders: ${metrics.totalWorkOrders}`,`At risk: ${metrics.atRisk}`,`Breached: ${metrics.breached}`,`Overdue: ${metrics.overdue}`,`Critical items: ${metrics.criticalItems}`,`Open escalations: ${metrics.openEscalations}`,...(commentary?["AI-generated management analysis",commentary.slice(0,80)]:[])];
  const stream=`BT /F1 16 Tf 50 780 Td ${lines.map((line,index)=>`${index?"0 -28 Td ":""}(${escapePdf(line)}) Tj`).join(" ")} ET`;
  const objects=["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"];
  let pdf="%PDF-1.4\n";const offsets=[0]; objects.forEach((object,index)=>{offsets.push(pdf.length);pdf+=`${index+1} 0 obj\n${object}\nendobj\n`;}); const xref=pdf.length;
  pdf+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n${offsets.slice(1).map(offset=>String(offset).padStart(10,"0")+" 00000 n ").join("\n")}\ntrailer << /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return new TextEncoder().encode(pdf);
}
