import { describe, expect, test } from "vitest";
import { DeterministicMockFmIntelligenceProvider, DisabledFmIntelligenceProvider } from "@/lib/ai/fm-intelligence";
import { evaluateSla, thresholdsReached } from "@/lib/sla/runtime";
import { managementReportCsv, managementReportPdf, type ManagementMetrics } from "@/lib/reports/management";
const metrics:ManagementMetrics={totalWorkOrders:10,slaEligible:8,slaMet:6,atRisk:1,breached:1,overdue:2,criticalItems:1,averageResponseMinutes:20,mttrMinutes:90,repeatFailures:1,pmCompliancePercent:95,assetAvailabilityPercent:98,openEscalations:2,byPriority:{critical:{total:1,met:1}}};
describe("SLA and reporting foundation",()=>{
 test("calculates deterministic SLA states",()=>{const c={startedAt:"2026-08-28T00:00:00Z",rectificationDeadline:"2026-08-28T01:40:00Z"};expect(evaluateSla(c,new Date("2026-08-28T00:50:00Z"))).toMatchObject({consumedPercent:50,state:"on_track"});expect(evaluateSla(c,new Date("2026-08-28T01:20:00Z"))).toMatchObject({consumedPercent:80,state:"at_risk"});expect(evaluateSla(c,new Date("2026-08-28T02:00:00Z"))).toMatchObject({state:"breached"})});
 test("applies threshold escalation",()=>{expect(thresholdsReached(91)).toEqual([50,75,90]);expect(thresholdsReached(1,true)).toEqual([0])});
 test("exports CSV and PDF",()=>{expect(managementReportCsv(metrics)).toContain('"slaEligible","8"');expect(new TextDecoder().decode(managementReportPdf("FMWorks",metrics).slice(0,8))).toBe("%PDF-1.4")});
 test("mock extraction needs human approval",async()=>{const r=await new DeterministicMockFmIntelligenceProvider().extractSlaAgreement({text:"P1 within four hours",sourceName:"Clause 4"});expect(r[0]).toMatchObject({humanApprovalState:"pending",sourceSection:"Clause 4"});expect(r[0].ambiguityWarning).toBeTruthy()});
 test("commentary uses only supplied metrics",async()=>{const r=await new DeterministicMockFmIntelligenceProvider().generateManagementSummary({metrics:{breached:2,compliance:95}});expect(r.metricKeysUsed).toEqual(["breached","compliance"]);expect(r.narrative).not.toMatch(/\b(?!2\b|95\b)\d+\b/)});
 test("AI outage leaves core monitoring operational",async()=>{await expect(new DisabledFmIntelligenceProvider().extractSlaAgreement({text:"x",sourceName:"x"})).rejects.toThrow("AI_PROVIDER_NOT_CONFIGURED");expect(evaluateSla({startedAt:"2026-08-28T00:00:00Z",rectificationDeadline:"2026-08-28T01:00:00Z"},new Date("2026-08-28T00:30:00Z")).state).toBe("on_track")});
});
