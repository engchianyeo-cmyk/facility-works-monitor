import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  canDeleteWorkOrder: vi.fn(),
  canEditWorkOrder: vi.fn(),
  createClient: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getCurrentIdentity: mocks.getCurrentIdentity,
}));

vi.mock("@/lib/permissions", () => ({
  canDeleteWorkOrder: mocks.canDeleteWorkOrder,
  canEditWorkOrder: mocks.canEditWorkOrder,
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.createClient,
}));

import {
  DELETE,
  PATCH,
} from "@/app/api/work-orders/[id]/route";

const WORK_ORDER_ID = "11111111-1111-4111-8111-111111111111";

const reviewerIdentity = {
  userId: "22222222-2222-4222-8222-222222222222",
  email: "reviewer@example.com",
  displayName: "Reviewer One",
  department: "Facilities",
  role: "reviewer" as const,
};

const administratorIdentity = {
  ...reviewerIdentity,
  userId: "33333333-3333-4333-8333-333333333333",
  email: "admin@example.com",
  displayName: "Administrator One",
  role: "administrator" as const,
};

type ExistingOrder = {
  title: string;
  location: string;
  category_id: string | null;
  priority: string | null;
  description: string | null;
  submitted_by: string | null;
  contact_number: string | null;
  updated_at: string;
  user_id: string;
  status: string;
};

const existingOrder: ExistingOrder = {
  title: "AHU vibration",
  location: "Level 3 Plant Room",
  category_id: null,
  priority: "high",
  description: "Abnormal vibration reported.",
  submitted_by: "Reviewer One",
  contact_number: null,
  updated_at: "2026-08-01T00:00:00.000Z",
  user_id: reviewerIdentity.userId,
  status: "submitted",
};

function routeContext(id = WORK_ORDER_ID) {
  return {
    params: Promise.resolve({ id }),
  };
}

function patchRequest(body: unknown): NextRequest {
  return new NextRequest(
    `http://localhost/api/work-orders/${WORK_ORDER_ID}`,
    {
      method: "PATCH",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
}

function deleteRequest(): NextRequest {
  return new NextRequest(
    `http://localhost/api/work-orders/${WORK_ORDER_ID}`,
    {
      method: "DELETE",
    },
  );
}

function createSingleQuery(result: { data: unknown; error: unknown }) {
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

function createRollbackQuery(result: { error: unknown }) {
  const query = {
    update: vi.fn(),
    eq: vi.fn(),
  };

  query.update.mockReturnValue(query);
  query.eq.mockResolvedValue(result);

  return query;
}

function createDeleteQuery(result: { error: unknown }) {
  const query = {
    delete: vi.fn(),
    eq: vi.fn(),
  };

  query.delete.mockReturnValue(query);
  query.eq.mockResolvedValue(result);

  return query;
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.getCurrentIdentity.mockResolvedValue(reviewerIdentity);
  mocks.canEditWorkOrder.mockReturnValue(true);
  mocks.canDeleteWorkOrder.mockReturnValue(true);
});

describe("PATCH /api/work-orders/[id]", () => {
  test("returns 401 when unauthenticated", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);

    const response = await PATCH(
      patchRequest({
        title: existingOrder.title,
        location: existingOrder.location,
      }),
      routeContext(),
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({
      error: "Authentication is required.",
    });
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test.each([
    {
      body: { location: "Level 3 Plant Room" },
      caseName: "missing title",
    },
    {
      body: { title: "AHU vibration" },
      caseName: "missing location",
    },
    {
      body: { title: " ", location: "Level 3 Plant Room" },
      caseName: "blank title",
    },
    {
      body: { title: "AHU vibration", location: " " },
      caseName: "blank location",
    },
  ])("returns 400 for $caseName", async ({ body }) => {
    const response = await PATCH(
      patchRequest(body),
      routeContext(),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Title and location are required.",
    });
  });

  test("returns 404 when the work order cannot be found", async () => {
    const lookupQuery = createSingleQuery({
      data: null,
      error: { message: "No rows returned" },
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    const response = await PATCH(
      patchRequest({
        title: existingOrder.title,
        location: existingOrder.location,
      }),
      routeContext(),
    );

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toEqual({
      error: "No rows returned",
    });
  });

  test("returns owner-specific 403 for a reviewer editing another user's order", async () => {
    const anotherUsersOrder: ExistingOrder = {
      ...existingOrder,
      user_id: "44444444-4444-4444-8444-444444444444",
    };

    const lookupQuery = createSingleQuery({
      data: anotherUsersOrder,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    mocks.canEditWorkOrder.mockReturnValue(false);

    const response = await PATCH(
      patchRequest({
        title: existingOrder.title,
        location: existingOrder.location,
      }),
      routeContext(),
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error:
        "Only the Reviewer who originally submitted this work order can edit it.",
    });
  });

  test("returns status-specific 403 for reviewer amendment after submission", async () => {
    const approvedOrder: ExistingOrder = {
      ...existingOrder,
      status: "approved",
    };

    const lookupQuery = createSingleQuery({
      data: approvedOrder,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    mocks.canEditWorkOrder.mockReturnValue(false);

    const response = await PATCH(
      patchRequest({
        title: approvedOrder.title,
        location: approvedOrder.location,
      }),
      routeContext(),
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error:
        "Reviewer amendments are allowed only while the work order is Submitted.",
    });
  });

  test("returns generic 403 for a role that cannot edit", async () => {
    mocks.getCurrentIdentity.mockResolvedValue({
      ...reviewerIdentity,
      role: "technician",
    });

    const lookupQuery = createSingleQuery({
      data: existingOrder,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(lookupQuery),
    });

    mocks.canEditWorkOrder.mockReturnValue(false);

    const response = await PATCH(
      patchRequest({
        title: existingOrder.title,
        location: existingOrder.location,
      }),
      routeContext(),
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "Your role cannot edit this work order.",
    });
  });

  test("returns existing data when there are no changes", async () => {
    const lookupQuery = createSingleQuery({
      data: existingOrder,
      error: null,
    });

    const from = vi.fn().mockReturnValue(lookupQuery);

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      patchRequest({
        title: existingOrder.title,
        location: existingOrder.location,
        category_id: existingOrder.category_id,
        priority: existingOrder.priority,
        description: existingOrder.description,
        contact_number: existingOrder.contact_number,
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      data: existingOrder,
    });

    expect(from).toHaveBeenCalledTimes(1);
  });

  test("updates changed fields and writes audit logs", async () => {
    const lookupQuery = createSingleQuery({
      data: existingOrder,
      error: null,
    });

    const updatedOrder = {
      ...existingOrder,
      title: "AHU severe vibration",
      priority: "critical",
      description: "Immediate inspection required.",
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
      patchRequest({
        title: " AHU severe vibration ",
        location: existingOrder.location,
        category_id: "",
        priority: " CRITICAL ",
        description: " Immediate inspection required. ",
        contact_number: "",
      }),
      routeContext(),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      data: updatedOrder,
    });

    expect(updateQuery.update).toHaveBeenCalledWith(
      expect.objectContaining({
        title: "AHU severe vibration",
        location: existingOrder.location,
        category_id: null,
        priority: "critical",
        description: "Immediate inspection required.",
        contact_number: null,
      }),
    );

    expect(activityInsert).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.objectContaining({
          user_id: reviewerIdentity.userId,
          work_order_id: WORK_ORDER_ID,
          action: "field_changed",
          actor: reviewerIdentity.displayName,
        }),
      ]),
    );
  });

  test("returns 500 when the update fails", async () => {
    const lookupQuery = createSingleQuery({
      data: existingOrder,
      error: null,
    });

    const updateQuery = createUpdateQuery({
      data: null,
      error: { message: "Update failed" },
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery);

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      patchRequest({
        title: "Changed title",
        location: existingOrder.location,
      }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Update failed",
    });
  });

  test("restores the previous data when audit insertion fails", async () => {
    const lookupQuery = createSingleQuery({
      data: existingOrder,
      error: null,
    });

    const updateQuery = createUpdateQuery({
      data: {
        ...existingOrder,
        title: "Changed title",
      },
      error: null,
    });

    const rollbackQuery = createRollbackQuery({
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery)
      .mockReturnValueOnce({
        insert: vi.fn().mockResolvedValue({
          error: { message: "Audit failed" },
        }),
      })
      .mockReturnValueOnce(rollbackQuery);

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      patchRequest({
        title: "Changed title",
        location: existingOrder.location,
      }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "The amendment audit failed. The work order was restored.",
    });

    expect(rollbackQuery.update).toHaveBeenCalledWith({
      title: existingOrder.title,
      location: existingOrder.location,
      category_id: existingOrder.category_id,
      priority: existingOrder.priority,
      description: existingOrder.description,
      contact_number: existingOrder.contact_number,
      updated_at: existingOrder.updated_at,
    });
  });

  test("reports when audit insertion and rollback both fail", async () => {
    const lookupQuery = createSingleQuery({
      data: existingOrder,
      error: null,
    });

    const updateQuery = createUpdateQuery({
      data: {
        ...existingOrder,
        title: "Changed title",
      },
      error: null,
    });

    const rollbackQuery = createRollbackQuery({
      error: { message: "Rollback failed" },
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(lookupQuery)
      .mockReturnValueOnce(updateQuery)
      .mockReturnValueOnce({
        insert: vi.fn().mockResolvedValue({
          error: { message: "Audit failed" },
        }),
      })
      .mockReturnValueOnce(rollbackQuery);

    mocks.createClient.mockResolvedValue({ from });

    const response = await PATCH(
      patchRequest({
        title: "Changed title",
        location: existingOrder.location,
      }),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error:
        "The amendment audit failed and the work order could not be restored automatically.",
    });
  });

  test("returns 500 for malformed JSON", async () => {
    const request = new NextRequest(
      `http://localhost/api/work-orders/${WORK_ORDER_ID}`,
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
      error: "Unable to update the work order.",
    });
  });
});

describe("DELETE /api/work-orders/[id]", () => {
  test("returns 401 when unauthenticated", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);

    const response = await DELETE(
      deleteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({
      error: "Authentication is required.",
    });
  });

  test("returns 403 when the role is not administrator", async () => {
    mocks.canDeleteWorkOrder.mockReturnValue(false);

    const response = await DELETE(
      deleteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "Administrator access is required.",
    });

    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("deletes a work order for an administrator", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(administratorIdentity);

    const deleteQuery = createDeleteQuery({
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(deleteQuery),
    });

    const response = await DELETE(
      deleteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      success: true,
    });

    expect(deleteQuery.delete).toHaveBeenCalled();
    expect(deleteQuery.eq).toHaveBeenCalledWith("id", WORK_ORDER_ID);
  });

  test("returns 500 when deletion fails", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(administratorIdentity);

    const deleteQuery = createDeleteQuery({
      error: { message: "Delete failed" },
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(deleteQuery),
    });

    const response = await DELETE(
      deleteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Delete failed",
    });
  });

  test("returns 500 when an unexpected exception occurs", async () => {
    mocks.getCurrentIdentity.mockRejectedValue(
      new Error("Authentication service unavailable"),
    );

    const response = await DELETE(
      deleteRequest(),
      routeContext(),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Unable to delete the work order.",
    });
  });
});
