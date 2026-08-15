import { describe, expect, test } from "vitest";
import { canActOnIncident, canManageRoster, canReportIncident } from "@/lib/incidents/permissions";
import { incidentSla } from "@/lib/incidents/sla";
import { INCIDENT_ACTIONS, INCIDENT_STATUSES, type IncidentStatus } from "@/lib/incidents/types";
import { canTransitionFrom, INCIDENT_TRANSITIONS } from "@/lib/incidents/workflow";

describe("emergency incident workflow", () => {
  test.each(INCIDENT_ACTIONS)("accepts only declared source states for %s", action => {
    for (const status of INCIDENT_STATUSES) expect(canTransitionFrom(status, action)).toBe(INCIDENT_TRANSITIONS[action].from.includes(status));
  });
  const base = { role: "technician" as const, actorId: "assigned", status: "reported" as IncidentStatus, assignedTechnicianId: "assigned" };
  test("assigned responder can acknowledge", () => expect(canActOnIncident("acknowledge", base)).toBe(true));
  test("another technician cannot acknowledge", () => expect(canActOnIncident("acknowledge", { ...base, actorId: "other" })).toBe(false));
  test("team member can acknowledge", () => expect(canActOnIncident("acknowledge", { ...base, actorId: "member", assignedTechnicianId: null, assignedTeamMember: true })).toBe(true));
  test("administrator can override and supervisor manages operational roster", () => { expect(canActOnIncident("acknowledge", { ...base, role: "administrator", actorId: "admin" })).toBe(true); expect(canManageRoster("supervisor")).toBe(true); });
  test("technician cannot report a general incident", () => { expect(canReportIncident("technician")).toBe(false); expect(canReportIncident("initiator")).toBe(true); });
});

describe("incident acknowledgement SLA", () => {
  test("reports time remaining before deadline", () => expect(incidentSla("2026-08-10T00:00:00Z", "2026-08-10T00:05:00Z", null, new Date("2026-08-10T00:03:00Z"))).toMatchObject({ acknowledged: false, elapsed_seconds: 180, time_remaining_seconds: 120, acknowledgement_overdue: false, escalation_required: false }));
  test("flags an unacknowledged incident after five minutes", () => expect(incidentSla("2026-08-10T00:00:00Z", "2026-08-10T00:05:00Z", null, new Date("2026-08-10T00:06:00Z"))).toMatchObject({ acknowledged: false, escalation_required: true, elapsed_seconds: 360, time_remaining_seconds: 0 }));
  test("stops elapsed time at acknowledgement", () => expect(incidentSla("2026-08-10T00:00:00Z", "2026-08-10T00:05:00Z", "2026-08-10T00:03:00Z", new Date("2026-08-10T00:10:00Z"))).toMatchObject({ acknowledged: true, escalation_required: false, elapsed_seconds: 180 }));
});
