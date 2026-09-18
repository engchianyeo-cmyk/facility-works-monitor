"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";

type CostLine = { id: string; cost_phase: string | null; cost_type: string; description: string; quantity: number; unit: string; unit_rate: number; amount: number };
type Quotation = { id?: string; quotation_ref?: string; quotation_date?: string; version_no?: number; status?: string; currency?: string; total_amount?: number; lines?: Array<Record<string, unknown>> };
type Rate = { id?: string; rate_item_id?: string; item_code?: string; description?: string; unit?: string; normal_unit_rate?: number; currency?: string };
type Rule = { rule_code?: string; minimum_quotations?: number; maximum_amount?: number };
type Financial = { currency: string; estimated_cost: number; quoted_cost: number | null; approved_budget: number | null; cost_status: string; recommended_at: string | null; financial_approved_at: string | null; financial_approval_note: string | null; rule?: Rule | Rule[] };
type Workspace = { costs: CostLine[]; procurement: Array<{ id:string; purchase_reference:string; description:string; currency:string; committed_amount:number; status:string }>; quotations: Quotation[]; rates: Rate[]; financial: Financial | null; contractor: { name?: string } | Array<{ name?: string }> | null; actual_costs_confirmed_at: string | null };

const money = (value: number | null | undefined) => value === null || value === undefined ? "Pending" : new Intl.NumberFormat("en-SG", { style: "currency", currency: "SGD" }).format(Number(value));
const input = "min-h-11 rounded border border-slate-300 bg-white px-3 text-sm";

export default function ReleaseOneWorkspace({ id, role, status }: { id:string; role:string; status:string }) {
  const router = useRouter();
  const [data,setData]=useState<Workspace|null>(null);
  const [error,setError]=useState<string|null>(null);
  const [message,setMessage]=useState<string|null>(null);
  const [busy,setBusy]=useState(false);
  const load=useCallback(async()=>{ const response=await fetch(`/api/work-orders/${id}/release-1`,{cache:"no-store"}); const body=await response.json(); if(!response.ok||!body.ok) throw new Error(body.message??"Cost workspace unavailable."); const workspace=body.data??{}; setData({costs:Array.isArray(workspace.costs)?workspace.costs:[],procurement:Array.isArray(workspace.procurement)?workspace.procurement:[],quotations:Array.isArray(workspace.quotations)?workspace.quotations:[],rates:Array.isArray(workspace.rates)?workspace.rates:[],financial:workspace.financial??null,contractor:workspace.contractor??null,actual_costs_confirmed_at:workspace.actual_costs_confirmed_at??null}); },[id]);
  useEffect(()=>{void load().catch((cause)=>setError(cause instanceof Error?cause.message:"Cost workspace unavailable."));},[load]);
  async function submit(operation:string,payload:Record<string,unknown>){setBusy(true);setError(null);setMessage(null);try{const response=await fetch(`/api/work-orders/${id}/release-1`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({operation,payload})});const body=await response.json();if(!response.ok||!body.ok)throw new Error(body.message??"Update failed.");await load();router.refresh();setMessage("Cost record updated and audited.");}catch(cause){setError(cause instanceof Error?cause.message:"Update failed.");}finally{setBusy(false);}}
  const technician=role==="technician"&&["assigned","in_progress"].includes(status);
  const manager=["supervisor","facility_manager","administrator"].includes(role);
  const financialApprover=["approver","supervisor","facility_manager","administrator"].includes(role);
  const actualCost=useMemo(()=>data?.costs.filter((line)=>line.cost_phase==="actual").reduce((sum,line)=>sum+Number(line.amount),0)??0,[data]);
  const proposedCost=useMemo(()=>data?.costs.filter((line)=>line.cost_phase!=="actual").reduce((sum,line)=>sum+Number(line.amount),0)??0,[data]);
  const latestQuote=data?.quotations.find((quote)=>quote.status==="submitted"||quote.status==="approved")??data?.quotations[0];
  const contractor=Array.isArray(data?.contractor)?data?.contractor[0]?.name:data?.contractor?.name;
  const rule=Array.isArray(data?.financial?.rule)?data?.financial?.rule[0]:data?.financial?.rule;
  const baseline=data?.financial?.approved_budget??data?.financial?.quoted_cost??(latestQuote?Number(latestQuote.total_amount):null);
  const variance=baseline===null||baseline===undefined?null:actualCost-Number(baseline);

  function quotation(event:FormEvent<HTMLFormElement>){event.preventDefault();const form=new FormData(event.currentTarget);const rate=data?.rates.find((item)=>String(item.id??item.rate_item_id)===String(form.get("rate_item_id")));void submit("quotation",{quotation_ref:form.get("quotation_ref"),quotation_date:form.get("quotation_date"),lines:[{rate_item_id:form.get("rate_item_id"),quantity:Number(form.get("quantity")),quoted_unit_rate:Number(form.get("quoted_unit_rate")),exception_reason:String(form.get("exception_reason")??"").trim()||undefined,description:String(rate?.description??"Quoted service"),unit:String(rate?.unit??"unit")}]});}

  return <section className="border-t border-neutral-200 pt-6" aria-labelledby="cost-summary-heading">
    <div><p className="text-xs font-black uppercase text-emerald-700">Release 1 commercial control</p><h2 id="cost-summary-heading" className="text-xl font-black text-slate-950">Cost Summary</h2><p className="mt-1 text-sm text-slate-600">Quotation, recommendation, actual cost and independent financial approval remain distinct audited steps.</p></div>
    {error&&<p role="alert" className="mt-3 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>}
    {message&&<p role="status" className="mt-3 rounded border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{message}</p>}
    {!data?<p className="mt-4 text-sm text-slate-500">Loading cost controls…</p>:<>
      <dl className="mt-4 grid gap-px overflow-hidden rounded-lg border bg-slate-200 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ["Estimated cost",money(data.financial?.estimated_cost??proposedCost)],
          ["Quoted cost",money(data.financial?.quoted_cost??(latestQuote?Number(latestQuote.total_amount):null))],
          ["Approved amount / budget",money(data.financial?.approved_budget)],
          ["Actual cost",money(actualCost)],
          ["Variance",money(variance)],
          ["Contractor",contractor??"Not assigned"],
          ["Quotation",latestQuote?.quotation_ref?`${latestQuote.quotation_ref} · ${money(Number(latestQuote.total_amount))}`:"Not recorded"],
          ["Cost status",(data.financial?.cost_status??"not configured").replaceAll("_"," ")],
          ["Financial approval",data.financial?.financial_approved_at?`Approved ${new Intl.DateTimeFormat("en-SG",{dateStyle:"medium"}).format(new Date(data.financial.financial_approved_at))}`:"Pending independent approval"],
          ["Quotation rule",`${rule?.minimum_quotations??1} quotation required below ${money(rule?.maximum_amount??1000)}`],
          ["Rule progress",`${data.quotations.filter((quote)=>["submitted","approved"].includes(String(quote.status))).length} of ${rule?.minimum_quotations??1} quotation recorded`],
          ["Actual costing",data.actual_costs_confirmed_at?"Technician confirmed":"Awaiting Technician confirmation"],
        ].map(([label,value])=><div key={label} className="bg-white p-4"><dt className="text-xs font-bold uppercase text-slate-500">{label}</dt><dd className="mt-1 font-bold capitalize text-slate-950">{value}</dd></div>)}
      </dl>

       <div className="mt-5 grid gap-5 lg:grid-cols-2">
        <section className="space-y-3"><h3 className="font-bold">Contractor quotation</h3>{data.quotations.map((quote,index)=><article key={String(quote.id??index)} className="rounded border bg-white p-3 text-sm"><div className="flex justify-between gap-3"><strong>{quote.quotation_ref??"Quotation"} · v{quote.version_no??1}</strong><strong>{money(Number(quote.total_amount??0))}</strong></div><p className="mt-1 text-slate-500">{quote.quotation_date??"Date not recorded"} · {quote.status??"submitted"}</p></article>)}{!data.quotations.length&&<p className="text-sm text-slate-500">No quotation recorded.</p>}
          {(technician||manager)&&data.rates.length>0&&(!data.financial||data.financial.cost_status==="draft")&&<form className="grid gap-3 rounded border bg-slate-50 p-4 sm:grid-cols-2" onSubmit={quotation}><input name="quotation_ref" required placeholder="Quotation reference" className={input}/><input name="quotation_date" required type="date" className={input}/><select name="rate_item_id" aria-label="Contractor rate item" className={`${input} sm:col-span-2`}>{data.rates.map((rate,index)=><option key={String(rate.id??rate.rate_item_id??index)} value={String(rate.id??rate.rate_item_id)}>{String(rate.item_code??rate.description??`Rate item ${index+1}`)} · {money(Number(rate.normal_unit_rate??0))}/{rate.unit}</option>)}</select><input name="quantity" required type="number" min="0.01" step="0.01" placeholder="Quantity" className={input}/><input name="quoted_unit_rate" required type="number" min="0" step="0.01" placeholder="Quoted unit rate" className={input}/><input name="exception_reason" placeholder="Rate exception reason, if needed" className={`${input} sm:col-span-2`}/><button disabled={busy} className="min-h-11 rounded bg-blue-700 px-4 font-bold text-white sm:col-span-2">Record quotation</button></form>}
          {technician&&data.quotations.length>0&&data.financial?.cost_status==="draft"&&<form className="grid gap-3 rounded border border-blue-200 bg-blue-50 p-4" onSubmit={(event)=>{event.preventDefault();void submit("recommend_cost",{note:String(new FormData(event.currentTarget).get("note")??"")});}}><label className="text-sm font-bold">Recommendation note<input name="note" required defaultValue="Reviewed against the configured one-quotation rule; recommend for independent approval." className={`mt-1 w-full ${input}`}/></label><button disabled={busy} className="min-h-11 rounded bg-blue-700 px-4 font-bold text-white">Recommend cost for approval</button><p className="text-xs text-blue-900">Technicians can record, review and recommend. They cannot approve expenditure.</p></form>}
        </section>

        <section className="space-y-3"><h3 className="font-bold">Actual cost</h3>{data.costs.filter((line)=>line.cost_phase==="actual").map((line)=><div key={line.id} className="flex justify-between rounded border bg-white p-3 text-sm"><span>{line.description} · {line.quantity} {line.unit}</span><strong>{money(Number(line.amount))}</strong></div>)}{!data.costs.some((line)=>line.cost_phase==="actual")&&<p className="text-sm text-slate-500">No actual cost recorded.</p>}
          {technician&&<form className="grid gap-3 rounded border bg-slate-50 p-4 sm:grid-cols-2" onSubmit={(event)=>{event.preventDefault();void submit("actual_cost",Object.fromEntries(new FormData(event.currentTarget)));}}><select name="cost_type" aria-label="Cost type" className={input}>{["labour","material","equipment","service","callout"].map((value)=><option key={value}>{value}</option>)}</select><input name="description" required placeholder="Description" className={input}/><input name="quantity" required type="number" min="0" step="0.01" placeholder="Quantity" className={input}/><input name="unit" required placeholder="Unit" className={input}/><input name="unit_rate" required type="number" min="0" step="0.01" placeholder="Unit rate (SGD)" className={input}/><input name="worker_name" placeholder="Worker (optional)" className={input}/><button disabled={busy} className="min-h-11 rounded bg-blue-700 px-4 font-bold text-white">Add actual cost</button><button type="button" disabled={busy} onClick={()=>void submit("confirm_actual_costs",{})} className="min-h-11 rounded border border-blue-700 bg-white px-4 font-bold text-blue-700">Confirm actual costing</button></form>}
          {financialApprover&&data.financial?.cost_status==="recommended"&&<form className="grid gap-3 rounded border border-emerald-200 bg-emerald-50 p-4" onSubmit={(event)=>{event.preventDefault();void submit("approve_financial",Object.fromEntries(new FormData(event.currentTarget)));}}><input name="approved_budget" required type="number" min="0" step="0.01" defaultValue={data.financial.quoted_cost??data.financial.estimated_cost} className={input}/><input name="note" required placeholder="Independent approval note" className={input}/><button disabled={busy} className="min-h-11 rounded bg-emerald-700 px-4 font-bold text-white">Approve financial commitment</button></form>}
         </section>
       </div>
       <section className="mt-5 space-y-3 border-t border-slate-200 pt-5"><h3 className="font-bold">Procurement commitments</h3>{data.procurement.map((item)=><article key={item.id} className="flex flex-wrap justify-between gap-3 rounded border bg-white p-3 text-sm"><div><strong>{item.purchase_reference} · {item.status}</strong><p>{item.description}</p></div><strong>{money(Number(item.committed_amount))}</strong></article>)}{!data.procurement.length&&<p className="text-sm text-slate-500">No procurement commitment recorded.</p>}
         {manager&&<form className="grid gap-3 rounded border bg-slate-50 p-4 sm:grid-cols-2" onSubmit={(event)=>{event.preventDefault();void submit("procurement",Object.fromEntries(new FormData(event.currentTarget)));}}><input name="purchase_reference" required placeholder="PO / commitment reference" className={input}/><input name="committed_amount" required type="number" min="0" step="0.01" placeholder="Committed SGD" className={input}/><input name="description" required placeholder="Scope / purpose" className={`${input} sm:col-span-2`}/><select name="status" aria-label="Procurement status" className={input}><option value="proposed">Proposed</option><option value="approved">Approved</option><option value="ordered">Ordered</option><option value="received">Received</option></select><button disabled={busy} className="min-h-11 rounded bg-emerald-700 px-4 font-bold text-white">Record commitment</button></form>}
       </section>
     </>}
  </section>;
}
