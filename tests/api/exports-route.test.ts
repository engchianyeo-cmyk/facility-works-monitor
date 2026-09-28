import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  createClient: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({ getCurrentIdentity: mocks.getCurrentIdentity }));
vi.mock("@/lib/supabase/server", () => ({ createClient: mocks.createClient }));

import { GET } from "@/app/api/exports/[register]/route";

const identity = {
  userId: "11111111-1111-4111-8111-111111111111",
  email: "manager@example.test",
  displayName: "Manager",
  department: "Facilities",
  role: "approver" as const,
  passwordChangeRequired: false,
};

const context = (register: string) => ({ params: Promise.resolve({ register }) });

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(identity);
});

describe("authenticated customer CSV exports", () => {
  test("denies anonymous access before creating a database client", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);
    const response = await GET(new Request("http://localhost/api/exports/work-orders"), context("work-orders"));
    expect(response.status).toBe(401);
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("denies a Technician whose normal visibility is narrower", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({ ...identity, role: "technician" });
    const response = await GET(new Request("http://localhost/api/exports/work-orders"), context("work-orders"));
    expect(response.status).toBe(403);
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("uses the authenticated RLS client and returns a controlled Work Order register", async () => {
    const order = vi.fn().mockResolvedValue({ data: [], error: null });
    const select = vi.fn().mockReturnValue({ order });
    const from = vi.fn().mockReturnValue({ select });
    mocks.createClient.mockResolvedValue({ from });

    const response = await GET(new Request("http://localhost/api/exports/work-orders"), context("work-orders"));
    expect(response.status).toBe(200);
    expect(mocks.createClient).toHaveBeenCalledTimes(1);
    expect(from).toHaveBeenCalledWith("work_orders");
    expect(response.headers.get("cache-control")).toContain("no-store");
    expect(response.headers.get("content-type")).toContain("text/csv; charset=utf-8");
    const csv = await response.text();
    expect(csv).toContain('"assignee_name"');
    expect(csv).toContain('"reviewed_at"');
    expect(csv).toContain('"closed_at"');
    expect(csv).not.toContain('"target_profile_id"');
  });

  test("derives Work Order assignment type from authoritative assignment columns", async () => {
    const workOrder = {
      id: "22222222-2222-4222-8222-222222222222",
      work_order_number: "FW-2026-000001",
      title: "=Formula probe",
      location: "Plant, room\nLevel 1",
      assigned_technician_id: "33333333-3333-4333-8333-333333333333",
      assigned_vendor_id: null,
      assigned_team_id: null,
      assigned_to: "UAT Technician",
      asset: { asset_tag: "UAT-AHU-001", name: "Synthetic AHU" },
    };
    const workOrderQuery = { select: vi.fn(), order: vi.fn() };
    workOrderQuery.select.mockReturnValue(workOrderQuery);
    workOrderQuery.order.mockResolvedValue({ data: [workOrder], error: null });
    const activityQuery = { select: vi.fn(), in: vi.fn(), eq: vi.fn() };
    activityQuery.select.mockReturnValue(activityQuery);
    activityQuery.in.mockReturnValue(activityQuery);
    activityQuery.eq.mockResolvedValue({ data: [], error: null });
    const from = vi.fn((table: string) => table === "work_orders" ? workOrderQuery : activityQuery);
    mocks.createClient.mockResolvedValue({ from });

    const response = await GET(new Request("http://localhost/api/exports/work-orders"), context("work-orders"));
    const csv = await response.text();
    expect(response.status).toBe(200);
    expect(workOrderQuery.select.mock.calls[0][0]).not.toContain("assigned_type");
    expect(workOrderQuery.select.mock.calls[0][0]).toContain("assigned_technician_id");
    expect(csv).toContain('"technician"');
    expect(csv).toContain('"UAT Technician"');
    expect(csv).toContain('"\'=Formula probe"');
    expect(csv).not.toContain("22222222-2222-4222-8222-222222222222");
    expect(csv).not.toContain("33333333-3333-4333-8333-333333333333");
  });

  test("derives Incident assignment type from the existing responder relationships", async () => {
    const query = { select: vi.fn(), order: vi.fn() };
    query.select.mockReturnValue(query);
    query.order.mockResolvedValue({ data: [{
      incident_number: "INC-2026-000001",
      location: "Plant, room\nLevel 1",
      description: "Synthetic incident",
      assigned_technician: null,
      assigned_team: { name: "Electrical Response" },
      incident_commander: { display_name: "UAT Supervisor" },
      asset: { asset_tag: "UAT-AHU-001", name: "Synthetic AHU" },
    }], error: null });
    mocks.createClient.mockResolvedValue({ from: vi.fn().mockReturnValue(query) });

    const response = await GET(new Request("http://localhost/api/exports/incidents"), context("incidents"));
    const csv = await response.text();
    expect(response.status).toBe(200);
    expect(query.select.mock.calls[0][0]).not.toContain(",assignment_type,");
    expect(csv).toContain('"team"');
    expect(csv).toContain('"Electrical Response"');
    expect(csv).toContain('"Plant, room\nLevel 1"');
  });

  test("exports PM outcomes through the authenticated compliance projection", async () => {
    const occurrenceQuery = { select: vi.fn(), order: vi.fn() };
    occurrenceQuery.select.mockReturnValue(occurrenceQuery);
    occurrenceQuery.order.mockResolvedValue({ data: [{
      id: "44444444-4444-4444-8444-444444444444",
      occurrence_number: 1,
      requirement: { requirement_number: "PMR-2026-000001", state: "active" },
      revision: { revision_number: 1, title: "Synthetic PM", maintenance_type: "preventive" },
      asset: { asset_tag: "UAT-AHU-001", name: "Synthetic AHU" },
      work_order: { work_order_number: "FW-2026-000001", status: "closed" },
    }], error: null });
    const complianceQuery = { select: vi.fn() };
    complianceQuery.select.mockResolvedValue({ data: [{ id: "44444444-4444-4444-8444-444444444444", compliance_state: "completed_on_time", deferral_count: 0 }], error: null });
    mocks.createClient.mockResolvedValue({ from: vi.fn((table: string) => table === "pm_occurrences" ? occurrenceQuery : complianceQuery) });

    const response = await GET(new Request("http://localhost/api/exports/pm-outcomes"), context("pm-outcomes"));
    const csv = await response.text();
    expect(response.status).toBe(200);
    expect(csv).toContain('"PMR-2026-000001"');
    expect(csv).toContain('"completed_on_time"');
    expect(csv).not.toContain("44444444-4444-4444-8444-444444444444");
  });
});
