import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  canAssignWorkOrderPersonnel: vi.fn(),
  createAdminClient: vi.fn(),
  createClient: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getCurrentIdentity: mocks.getCurrentIdentity,
}));

vi.mock("@/lib/permissions", () => ({
  canAssignWorkOrderPersonnel: mocks.canAssignWorkOrderPersonnel,
}));

vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: mocks.createAdminClient,
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.createClient,
}));

import { PATCH } from "@/app/api/work-orders/[id]/assignment/route";

const WORK_ORDER_ID = "11111111-1111-4111-8111-111111111111";
const TECHNICIAN_ID = "22222222-2222-4222-8222-222222222222";
const OTHER_TECHNICIAN_ID = "33333333-3333-4333-8333-333333333333";

const identity = {
  userId: "44444444-4444-4444-8444-444444444444",
  email: "approver@example.com",
  displayName: "Approver One",
  department: "Facilities",
  role: "approver" as const,
};

type AssignmentOrder = {
  status: string;
  assigned_technician_id: string | null;
  assigned_to: string | null;
  assigned_by: string | null;
  assigned_at: string | null;
  updated_at: string;
};

const baseOrder: AssignmentOrder = {
  status: "approved",
  assigned_technician_id: null,
  assigned_to: null,
  assigned_by: null,
  assigned_at: null,
  updated_at: "2026-08-01T00:00:00.000Z",
};

const technician = {
  id: TECHNICIAN_ID,
  display_name: "Technician One",
  role: "technician",
  is_active: true,
  deleted_at: null,
};

function createRequest(body: unknown): NextRequest {
  return new NextRequest(
    `http://localhost/api/work-orders/${WORK_ORDER_ID}/assignment`,
    {
      method: "PATCH",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
}

function routeContext(id = WORK_ORDER_ID) {
  return {
    params: Promise.resolve({ id }),
  };
}

function createLookupQuery(result: { data: unknown; error: unknown }) {
  const query = {
    select: vi.fn(),
    eq: vi.fn(),
    single: vi.fn(),
  };

  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.single.mockResolvedValue(result);

  return query;
}

function createTechnicianQuery(result: { data: unknown; error: unknown }) {
  const query = {
    select: vi.fn(),
    eq: vi.fn(),
    is: vi.fn(),
    maybeSingle: vi.fn(),
  };

  query.select.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.is.mockReturnValue(query);
  query.maybeSingle.mockResolvedValue(result);

  return query;
}

function createUpdateQuery(result: { data: unknown; error: unknown }) {
  const query = {
    update: vi.fn(),
    eq: vi.fn(),
    select: vi.fn(),
    single: vi.fn(),
  };

  query.update.mockReturnValue(query);
  query.eq.mockReturnValue(query);
  query.select.mockReturnValue(query);
  query.single.mockResolvedValue(result);

  return query;
}

function createRollbackQuery(result: { data?: unknown; error: unknown }) {
  const query = {
    update: vi.fn(),
    eq: vi.fn(),
  };

  query.update.mockReturnValue(query);
  query.eq.mockResolvedValue(result);

  return query;
}

function configureSuccessfulClients(options?: {
  order?: AssignmentOrder;
  updateData?: Record<string, unknown>;
  auditError?: unknown;
}) {
  const order = options?.order ?? baseOrder;
  const updateData = options?.updateData ?? {
    ...order,
    assigned_technician_id: TECHNICIAN_ID,
    assigned_to: technician.display_name,
  };

  const lookupQuery = createLookupQuery({
    data: order,
    error: null,
  });

  const updateQuery = createUpdateQuery({
    data: updateData,
    error: null,
  });

  const auditInsert = vi.fn().mockResolvedValue({
    error: options?.auditError ?? null,
  });

  const ordinaryFrom = vi
    .fn()
    .mockReturnValueOnce(lookupQuery)
    .mockReturnValueOnce(updateQuery)
    .mockReturnValueOnce({
      insert: auditInsert,
    });

  mocks.createClient.mockResolvedValue({
    from: ordinaryFrom,
  });

  const technicianQuery = createTechnicianQuery({
    data: technician,
    error: null,
  });

  mocks.createAdminClient.mockReturnValue({
    from: vi.fn().mockReturnValue(technicianQuery),
  });

  return {
    ordinaryFrom,
    lookupQuery,
    updateQuery,
    auditInsert,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(identity);
  mocks.canAssignWorkOrderPersonnel.mockReturnValue(true);
});

describe("PATCH work-order personnel assignment", () => {
  test("returns 401 when no user is authenticated", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({
      error: "Authentication is required.",
    });

    expect(mocks.createClient).not.toHaveBeenCalled();
    expect(mocks.createAdminClient).not.toHaveBeenCalled();
  });

  test.each([
    "",
    "not-a-uuid",
    "11111111-1111-1111-1111-111111111111",
  ])("returns 400 for invalid technician ID: %s", async (technicianId) => {
    const response = await PATCH(
      createRequest({ technician_id: technicianId }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Select a valid technician.",
    });

    expect(mocks.createClient).not.toHaveBeenCalled();
    expect(mocks.createAdminClient).not.toHaveBeenCalled();
  });

  test("returns 404 when the work order cannot be found", async () => {
    const lookupQuery = createLookupQuery({
      data: null,
      error: { message: "No rows returned" },
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({
      error: "Work order not found.",
    });
  });

  test("returns 403 when the work-order status does not allow assignment", async () => {
    const submittedOrder: AssignmentOrder = {
      ...baseOrder,
      status: "submitted",
    };

    const lookupQuery = createLookupQuery({
      data: submittedOrder,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    mocks.canAssignWorkOrderPersonnel.mockReturnValue(false);

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error:
        "Personnel can be assigned only after the work order is approved.",
    });
  });

  test("returns 403 when the authenticated role cannot assign personnel", async () => {
    const lookupQuery = createLookupQuery({
      data: baseOrder,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    mocks.canAssignWorkOrderPersonnel.mockReturnValue(false);

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "Your role cannot assign work-order personnel.",
    });
  });

  test("returns 400 when the technician is inactive or ineligible", async () => {
    const lookupQuery = createLookupQuery({
      data: baseOrder,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    const technicianQuery = createTechnicianQuery({
      data: null,
      error: { message: "Technician not found" },
    });

    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue(technicianQuery),
    });

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "The selected technician is not active or eligible.",
    });
  });

  test("returns the existing assignment without writing when already assigned", async () => {
    const alreadyAssignedOrder: AssignmentOrder = {
      ...baseOrder,
      assigned_technician_id: TECHNICIAN_ID,
      assigned_to: technician.display_name,
    };

    const lookupQuery = createLookupQuery({
      data: alreadyAssignedOrder,
      error: null,
    });

    const ordinaryFrom = vi.fn().mockReturnValue(lookupQuery);

    mocks.createClient.mockResolvedValue({
      from: ordinaryFrom,
    });

    const technicianQuery = createTechnicianQuery({
      data: technician,
      error: null,
    });

    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue(technicianQuery),
    });

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(200);

    await expect(response.json()).resolves.toEqual({
      data: alreadyAssignedOrder,
      message: "This technician is already assigned.",
    });

    expect(ordinaryFrom).toHaveBeenCalledTimes(1);
  });

  test("returns 500 when the assignment update fails", async () => {
    const lookupQuery = createLookupQuery({
      data: baseOrder,
      error: null,
    });

    const updateQuery = createUpdateQuery({
      data: null,
      error: { message: "Database update failed" },
    });

    const ordinaryFrom = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery);

    mocks.createClient.mockResolvedValue({
      from: ordinaryFrom,
    });

    const technicianQuery = createTechnicianQuery({
      data: technician,
      error: null,
    });

    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue(technicianQuery),
    });

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Database update failed",
    });
  });

  test("assigns an eligible technician and records the audit event", async () => {
    const { updateQuery, auditInsert } = configureSuccessfulClients();

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(200);

    const body = await response.json();
    expect(body.data.assigned_technician_id).toBe(TECHNICIAN_ID);
    expect(body.data.assigned_to).toBe("Technician One");

    expect(updateQuery.update).toHaveBeenCalledWith(
      expect.objectContaining({
        assigned_technician_id: TECHNICIAN_ID,
        assigned_to: "Technician One",
        assigned_by: "Approver One",
      }),
    );

    expect(auditInsert).toHaveBeenCalledWith(
      expect.objectContaining({
        user_id: identity.userId,
        work_order_id: WORK_ORDER_ID,
        action: "personnel_assigned",
        actor: "Approver One",
      }),
    );
  });

  test("records a reassignment action when replacing a technician", async () => {
    const previousOrder: AssignmentOrder = {
      ...baseOrder,
      assigned_technician_id: OTHER_TECHNICIAN_ID,
      assigned_to: "Technician Two",
      assigned_by: "Supervisor One",
      assigned_at: "2026-07-31T10:00:00.000Z",
    };

    const { auditInsert } = configureSuccessfulClients({
      order: previousOrder,
    });

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(200);

    expect(auditInsert).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "personnel_reassigned",
      }),
    );

    const auditCall = auditInsert.mock.calls[0]?.[0];
    const note = JSON.parse(String(auditCall.note));

    expect(note).toEqual({
      previous_technician_id: OTHER_TECHNICIAN_ID,
      previous_technician_name: "Technician Two",
      technician_id: TECHNICIAN_ID,
      technician_name: "Technician One",
    });
  });

  test("rolls back the assignment when audit insertion fails", async () => {
    const lookupQuery = createLookupQuery({
      data: baseOrder,
      error: null,
    });

    const updateQuery = createUpdateQuery({
      data: {
        ...baseOrder,
        assigned_technician_id: TECHNICIAN_ID,
        assigned_to: technician.display_name,
      },
      error: null,
    });

    const auditInsert = vi.fn().mockResolvedValue({
      error: { message: "Audit insert failed" },
    });

    const rollbackQuery = createRollbackQuery({
      error: null,
    });

    const ordinaryFrom = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery)
      .mockReturnValueOnce({ insert: auditInsert })
      .mockReturnValueOnce(rollbackQuery);

    mocks.createClient.mockResolvedValue({
      from: ordinaryFrom,
    });

    const technicianQuery = createTechnicianQuery({
      data: technician,
      error: null,
    });

    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue(technicianQuery),
    });

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error:
        "The assignment audit failed. The previous assignment was restored.",
    });

    expect(rollbackQuery.update).toHaveBeenCalledWith({
      assigned_technician_id: null,
      assigned_to: null,
      assigned_by: null,
      assigned_at: null,
      updated_at: baseOrder.updated_at,
    });
  });

  test("reports when both audit and rollback fail", async () => {
    const lookupQuery = createLookupQuery({
      data: baseOrder,
      error: null,
    });

    const updateQuery = createUpdateQuery({
      data: {
        ...baseOrder,
        assigned_technician_id: TECHNICIAN_ID,
      },
      error: null,
    });

    const rollbackQuery = createRollbackQuery({
      error: { message: "Rollback failed" },
    });

    const ordinaryFrom = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery)
      .mockReturnValueOnce({
        insert: vi.fn().mockResolvedValue({
          error: { message: "Audit insert failed" },
        }),
      })
      .mockReturnValueOnce(rollbackQuery);

    mocks.createClient.mockResolvedValue({
      from: ordinaryFrom,
    });

    const technicianQuery = createTechnicianQuery({
      data: technician,
      error: null,
    });

    mocks.createAdminClient.mockReturnValue({
      from: vi.fn().mockReturnValue(technicianQuery),
    });

    const response = await PATCH(
      createRequest({ technician_id: TECHNICIAN_ID }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error:
        "The assignment audit failed and the previous assignment could not be restored automatically.",
    });
  });
});
