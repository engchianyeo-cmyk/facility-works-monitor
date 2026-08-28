export type HumanApprovalState = "pending" | "approved_for_draft" | "rejected";

export type ProposedSlaRule = {
  priorityClass: "P1" | "P2" | "P3" | "P4";
  acknowledgementMinutes?: number;
  responseMinutes?: number;
  attendanceMinutes?: number;
  makeSafeMinutes?: number;
  rectificationMinutes: number;
  kpiTargetPercent: number;
};

export type SlaExtraction = {
  sourceDocument?: string;
  sourcePage?: string;
  sourceSection?: string;
  sourceClause?: string;
  extractedObligation: string;
  proposedRule: ProposedSlaRule;
  confidence: number;
  ambiguityWarning?: string;
  sourceExcerpt?: string;
  serviceCategory?: string;
  assetSystem?: string;
  restorationMinutes?: number;
  operatingHours?: string;
  serviceAvailability?: string;
  plannedMaintenanceRequirement?: string;
  statutoryRequirement?: string;
  reportingRequirement?: string;
  escalationRequirement?: string;
  serviceCreditReference?: string;
  exclusions?: string[];
  dependencies?: string[];
  assumptions?: string[];
  aiExplanation?: string;
  humanApprovalState: HumanApprovalState;
};

export type VerifiedManagementMetrics = Readonly<Record<string, number | string | null>>;
export type ManagementSummary = { narrative: string; metricKeysUsed: string[]; generatedBy: string };

export interface FmIntelligenceProvider {
  readonly key: string;
  extractSlaAgreement(input: { text: string; sourceName: string }): Promise<SlaExtraction[]>;
  analyseStaffingRequirements(input: { obligations: SlaExtraction[] }): Promise<{ observations: string[] }>;
  explainSlaRisk(input: { metrics: VerifiedManagementMetrics }): Promise<{ explanation: string }>;
  generateManagementSummary(input: { metrics: VerifiedManagementMetrics }): Promise<ManagementSummary>;
}

export class DisabledFmIntelligenceProvider implements FmIntelligenceProvider {
  readonly key: string = "disabled";
  private unavailable(): never { throw new Error("AI_PROVIDER_NOT_CONFIGURED"); }
  async extractSlaAgreement(input: { text: string; sourceName: string }): Promise<SlaExtraction[]> { void input; return this.unavailable(); }
  async analyseStaffingRequirements(input: { obligations: SlaExtraction[] }): Promise<{ observations: string[] }> { void input; return this.unavailable(); }
  async explainSlaRisk(input: { metrics: VerifiedManagementMetrics }): Promise<{ explanation: string }> { void input; return this.unavailable(); }
  async generateManagementSummary(input: { metrics: VerifiedManagementMetrics }): Promise<ManagementSummary> { void input; return this.unavailable(); }
}

export class TimeoutFmIntelligenceProvider extends DisabledFmIntelligenceProvider {
  override readonly key = "timeout";
  override async extractSlaAgreement(input: { text: string; sourceName: string }): Promise<SlaExtraction[]> { void input; throw new Error("AI_PROVIDER_TIMEOUT"); }
}

export class DeterministicMockFmIntelligenceProvider implements FmIntelligenceProvider {
  readonly key = "deterministic-mock";
  async extractSlaAgreement(input: { text: string; sourceName: string }): Promise<SlaExtraction[]> {
    return [{ sourceDocument:input.sourceName,sourceSection: input.sourceName,sourceClause:"MOCK-1",sourceExcerpt:input.text.trim().slice(0,240), extractedObligation: input.text.trim(), proposedRule: { priorityClass: "P1", acknowledgementMinutes: 15, responseMinutes: 30, attendanceMinutes: 60, makeSafeMinutes: 120, rectificationMinutes: 240, kpiTargetPercent: 95 }, confidence: 0.5, ambiguityWarning: "Mock extraction requires clause-level human validation.",assumptions:["Pilot mock values require source verification"],aiExplanation:"Deterministic mock classification; no external provider was called.", humanApprovalState: "pending" }];
  }
  async analyseStaffingRequirements(input: { obligations: SlaExtraction[] }) { return { observations: [`${input.obligations.length} proposed obligation(s) require human staffing review.`] }; }
  async explainSlaRisk(input: { metrics: VerifiedManagementMetrics }) { return { explanation: `Deterministic risk explanation from ${Object.keys(input.metrics).length} verified metric(s).` }; }
  async generateManagementSummary(input: { metrics: VerifiedManagementMetrics }): Promise<ManagementSummary> {
    const entries = Object.entries(input.metrics).sort(([a],[b]) => a.localeCompare(b));
    return { narrative: entries.map(([key,value]) => `${key}: ${value ?? "not available"}`).join("; "), metricKeysUsed: entries.map(([key]) => key), generatedBy: this.key };
  }
}

export const fmIntelligence: FmIntelligenceProvider = new DisabledFmIntelligenceProvider();
