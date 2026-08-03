import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  canPerformWorkOrderAction: vi.fn(),
  createClient: vi.fn(),
  nextStatus: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getCurrentIdentity: mocks.getCurrentIdentity,
}));

vi.mock("@/lib/permissions", () => ({
  canPerformWorkOrderAction: mocks.canPerformWorkOrderAction,
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.createClient,
}));

vi.mock("@/lib/status", async () => {
  const actual = await vi.importActual<typeof import("@/lib/status")>(
    "@/lib/status",
  );

  return {
    ...actual,
    nextStatus: mocks.nextStatus,
  };
});

import { PATCH } from "@/app/api/work-orders/[id]/status/route";

const WORK_ORDER_ID = "11111111-1111-4111-8111-111111111111";

const approverIdentity = {
  userId: "22222222-2222-4222-8222-222222222222",
  email: "approver@example.com",
  displayName: "Approver One",
  department: "Facilities",
  role: "approver" as const,
};

const technicianIdentity = {
  userId: "33333333-3333-4333-8333-333333333333",
  email: "technician@example.com",
  displayName: "Technician One",
  department: "Facilities",
  role: "technician" as const,
};

type ExistingOrder = {
  status: string;
  user_id: string;
  assigned_technician_id: string | null;
};

const submittedOrder: ExistingOrder = {
  status: "submitted",
  user_id: "44444444-4444-4444-8444-444444444444",
  assigned_technician_id: null,
};

function routeContext(id = WORK_ORDER_ID) {
  return {
    params: Promise.resolve({ id }),
  };
}

function createRequest(body: unknown): NextRequest {
  return new NextRequest(
    `http://localhost/api/work-orders/${WORK_ORDER_ID}/status`,
    {
      method: "PATCH",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
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

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(approverIdentity);
  mocks.canPerformWorkOrderAction.mockReturnValue(true);
  mocks.nextStatus.mockReturnValue({
    ok: true,
    to: "approved",
  });
});

describe("PATCH /api/work-orders/[id]/status", () => {
  test("returns 401 when unauthenticated", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);

    const response = await PATCH(
      createRequest({ action: "approve" }),
      routeContext(),
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({
      error: "Authentication is required.",
    });

    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test.each([
    "",
    "archive",
    "APPROVE",
  ])("returns 400 for invalid action: %s", async (action) => {
    const response = await PATCH(
      createRequest({ action }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: `Invalid action: ${action.trim()}`,
    });

    expect(mocks.createClient).not.toHaveBeenCalled();
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
      createRequest({ action: "approve" }),
      routeContext(),
    );

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({
      error: "Work order not found.",
    });
  });

  test("returns 403 when the role cannot perform the action", async () => {
    const lookupQuery = createLookupQuery({
      data: submittedOrder,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    mocks.canPerformWorkOrderAction.mockReturnValue(false);

    const response = await PATCH(
      createRequest({ action: "approve" }),
      routeContext(),
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "Your role cannot perform this action.",
    });
  });

  test("passes identity and assignment context to the permission check", async () => {
    const approvedOrder: ExistingOrder = {
      status: "approved",
      user_id: submittedOrder.user_id,
      assigned_technician_id: technicianIdentity.userId,
    };

    const lookupQuery = createLookupQuery({
      data: approvedOrder,
      error: null,
    });

    mocks.getCurrentIdentity.mockResolvedValue(technicianIdentity);
    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });
    mocks.nextStatus.mockReturnValue({
      ok: true,
      to: "in_progress",
    });

    const updateQuery = createUpdateQuery({
      data: {
        ...approvedOrder,
        status: "in_progress",
      },
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery)
      .mockReturnValueOnce({
        insert: vi.fn().mockResolvedValue({ error: null }),
      });

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      createRequest({ action: "start" }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    expect(mocks.canPerformWorkOrderAction).toHaveBeenCalledWith(
      "start",
      {
        role: "technician",
        userId: technicianIdentity.userId,
        ownerId: approvedOrder.user_id,
        assignedTechnicianId: technicianIdentity.userId,
        status: "approved",
      },
    );
  });

  test("returns 400 for an invalid status transition", async () => {
    const lookupQuery = createLookupQuery({
      data: {
        ...submittedOrder,
        status: "approved",
      },
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    mocks.nextStatus.mockReturnValue({
      ok: false,
      error: 'Cannot approve a work order that is "approved". Valid from: submitted',
    });

    const response = await PATCH(
      createRequest({ action: "approve" }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error:
        'Cannot approve a work order that is "approved". Valid from: submitted',
    });
  });

  test("requires a rejection reason", async () => {
    const lookupQuery = createLookupQuery({
      data: submittedOrder,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    mocks.nextStatus.mockReturnValue({
      ok: true,
      to: "rejected",
    });

    const response = await PATCH(
      createRequest({
        action: "reject",
        note: "   ",
      }),
      routeContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Rejection reason is required.",
    });
  });

  test("returns 500 when the status update fails", async () => {
    const lookupQuery = createLookupQuery({
      data: submittedOrder,
      error: null,
    });

    const updateQuery = createUpdateQuery({
      data: null,
      error: { message: "Status update failed" },
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery);

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      createRequest({ action: "approve" }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Status update failed",
    });
  });

  test("returns a generic 500 when the update yields no data", async () => {
    const lookupQuery = createLookupQuery({
      data: submittedOrder,
      error: null,
    });

    const updateQuery = createUpdateQuery({
      data: null,
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery);

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      createRequest({ action: "approve" }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Unable to update work order status.",
    });
  });

  test("approves a submitted work order and records the activity log", async () => {
    const lookupQuery = createLookupQuery({
      data: submittedOrder,
      error: null,
    });

    const updatedOrder = {
      ...submittedOrder,
      status: "approved",
    };

    const updateQuery = createUpdateQuery({
      data: updatedOrder,
      error: null,
    });

    const activityInsert = vi.fn().mockResolvedValue({
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery)
      .mockReturnValueOnce({
        insert: activityInsert,
      });

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      createRequest({
        action: "approve",
        note: "Approved after review.",
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      data: updatedOrder,
    });

    expect(updateQuery.update).toHaveBeenCalledWith(
      expect.objectContaining({
        status: "approved",
      }),
    );

    expect(activityInsert).toHaveBeenCalledWith({
      user_id: approverIdentity.userId,
      work_order_id: WORK_ORDER_ID,
      action: "status_change",
      from_status: "submitted",
      to_status: "approved",
      actor: approverIdentity.displayName,
      note: "Approved after review.",
    });
  });

  test("rejects a submitted work order and records the trimmed reason", async () => {
    const lookupQuery = createLookupQuery({
      data: submittedOrder,
      error: null,
    });

    const updatedOrder = {
      ...submittedOrder,
      status: "rejected",
    };

    const updateQuery = createUpdateQuery({
      data: updatedOrder,
      error: null,
    });

    const activityInsert = vi.fn().mockResolvedValue({
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery)
      .mockReturnValueOnce({
        insert: activityInsert,
      });

    mocks.createClient.mockResolvedValue({ from });
    mocks.nextStatus.mockReturnValue({
      ok: true,
      to: "rejected",
    });

    const response = await PATCH(
      createRequest({
        action: "reject",
        note: "  Quotation is incomplete.  ",
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    expect(activityInsert).toHaveBeenCalledWith(
      expect.objectContaining({
        from_status: "submitted",
        to_status: "rejected",
        note: "Quotation is incomplete.",
      }),
    );
  });

  test("returns 500 when activity logging fails after the status update", async () => {
    const lookupQuery = createLookupQuery({
      data: submittedOrder,
      error: null,
    });

    const updatedOrder = {
      ...submittedOrder,
      status: "approved",
    };

    const updateQuery = createUpdateQuery({
      data: updatedOrder,
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery)
      .mockReturnValueOnce({
        insert: vi.fn().mockResolvedValue({
          error: { message: "Activity insert failed" },
        }),
      });

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      createRequest({ action: "approve" }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Status updated but activity log failed.",
    });
  });

  test("returns 500 for malformed JSON", async () => {
    const request = new NextRequest(
      `http://localhost/api/work-orders/${WORK_ORDER_ID}/status`,
      {
        method: "PATCH",
        headers: {
          "content-type": "application/json",
        },
        body: "{invalid-json",
      },
    );

    const response = await PATCH(request, routeContext());

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Internal Server Error",
    });
  });
});
