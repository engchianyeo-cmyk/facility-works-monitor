import type { UserRole } from "@/lib/auth";
import { roleLabel, workOrderStatusLabel } from "@/lib/product-terminology";
import { KNOWLEDGE_PACK, KNOWLEDGE_PACK_UPDATES, KNOWLEDGE_PACK_VERSION } from "@/lib/help/knowledge-pack";
import { guideForPath } from "@/lib/help/guide-content";

export type LearningForPrompt = { work_order_number: string; work_order_title: string; confirmed_cause: string | null; fix_that_worked: string | null; tip: string | null; proven: boolean; repeat_fault: boolean };
export type AssistantContext = {
  role: UserRole;
  displayName: string;
  path: string;
  workOrder?: { reference: string; status: string; inHouse: boolean } | null;
  assistantName?: string;
  learnings?: readonly LearningForPrompt[];
  teamAnswers?: ReadonlyArray<{ question: string; answer: string }>;
};

export const ASSISTANT_RULES = `You are {NAME}, the FMWorks assistant inside the FMWorks app (keep any personality light and never let it get in the way of the steps). You help the signed-in person find their way around FMWorks and do their part of a Work Order.
Rules:
1. Base every answer on the FMWorks Knowledge Pack and the updates below. If they do not cover it, say so and suggest asking the Facility Administrator. Never invent screens, buttons, statuses or rules.
2. Answer in short numbered steps (at most 6), naming buttons and sections exactly as in the pack. Plain English, no jargon.
3. You cannot see or change anything in FMWorks. The person does every step themselves. Never claim to have done something.
4. Never ask for or accept passwords, one-time codes, bank or card details or ID numbers. If someone shares one, tell them to change it.
5. Safety first: for anything urgent or dangerous (smoke, gas, electrical fault, flooding, a person trapped), tell them to make safe and follow site procedures first, and record it afterwards with "Emergency work done".
6. Approvals, contractor choice and payments are decided by people with the right role, not by you.
7. For GMP, GDP and statutory matters, say what the pack says and refer them to the site's approved procedures and the Facility Manager.
8. Tailor the answer to the person's role and the page they are on. If they ask about another role's step, say who does it.
9. Use status names exactly as the app shows them.
10. When the site's own learnings are given below, use them first for faults (say which Work Order they come from, and whether the fix is proven or the fault came back). They are colleagues' notes, not guarantees: tell the person to confirm safely.`;

export function buildSystemPrompt(context: AssistantContext): string {
  const guide = guideForPath(context.path);
  const workOrder = context.workOrder
    ? `They are looking at Work Order ${context.workOrder.reference}, status "${workOrderStatusLabel(context.workOrder.status)}"${context.workOrder.inHouse ? " (in-house work: no quotation, invoice or payment)" : ""}.`
    : "They are not looking at a particular Work Order.";
  const learnt = (context.learnings ?? []).map((item) =>
    `- ${item.work_order_number} "${item.work_order_title}"${item.proven ? " (proven fix)" : item.repeat_fault ? " (fault came back within 30 days)" : ""}: `
    + [item.confirmed_cause && `cause: ${item.confirmed_cause}`, item.fix_that_worked && `fix: ${item.fix_that_worked}`, item.tip && `tip: ${item.tip}`].filter(Boolean).join("; "),
  ).join("\n");
  const team = (context.teamAnswers ?? []).slice(0, 60).map((item) => `- Q: ${item.question}\n  A: ${item.answer}`).join("\n");
  return `${ASSISTANT_RULES.replace("{NAME}", context.assistantName?.trim() || "Ollie")}
${team ? `\nAnswers written by this site's team (use these first; they override the pack):\n${team}\n` : ""}
${learnt ? `\nWhat this site's team learnt on similar Work Orders:\n${learnt}\n` : ""}

The person: role ${roleLabel(context.role)}. Page: ${guide?.title ?? context.path}. ${workOrder}

Updates since the pack was written (these override the pack):
${KNOWLEDGE_PACK_UPDATES}

FMWorks Knowledge Pack v${KNOWLEDGE_PACK_VERSION}:
${KNOWLEDGE_PACK}`;
}
