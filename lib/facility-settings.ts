/** D-11: when the second Technician endorses a Work Order. The default is the owner's recommended option. */
export const ENDORSEMENT_STAGES = [
  { value: "before_review", label: "Before the Approver's review (recommended)", help: "The second Technician checks the completed work before the Approver reviews it." },
  { value: "before_submission", label: "Before submission", help: "The second Technician checks the Draft — site, photos and quotation — before it is submitted for approval. Emergency work is endorsed before the review instead." },
  { value: "both", label: "Both", help: "Endorsed before submission and again before the Approver's review." },
] as const;

export type EndorsementStage = (typeof ENDORSEMENT_STAGES)[number]["value"];
export const DEFAULT_ENDORSEMENT_STAGE: EndorsementStage = "before_review";

export function endorsementStageLabel(value: string | null | undefined) {
  return ENDORSEMENT_STAGES.find((stage) => stage.value === value)?.label ?? ENDORSEMENT_STAGES[0].label;
}
