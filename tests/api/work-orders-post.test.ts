import { beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getCurrentIdentity: vi.fn(),
  canCreateWorkOrder: vi.fn(),
  createClient: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getCurrentIdentity: mocks.getCurrentIdentity,
}));

vi.mock("@/lib/permissions", () => ({
  canCreateWorkOrder: mocks.canCreateWorkOrder,
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.createClient,
}));

import { POST } from "@/app/api/work-orders/route";

const identity = {
  userId: "11111111-1111-4111-8111-111111111111",
  email: "reviewer@example.com",
  displayName: "Reviewer One",
  department: "Facilities",
  role: "reviewer" as const,
};

const createdOrder = {
  id: "22222222-2222-4222-8222-222222222222",
  user_id: identity.userId,
  title: "AHU vibration",
  location: "Level 3 Plant Room",
  category_id: null,
  priority: "high",
  description: "Abnormal vibration reported.",
  submitted_by: identity.displayName,
  contact_number: null,
  status: "submitted",
};

function createRequest(body: unknown): Request {
  return new Request("http://localhost/api/work-orders", {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function createInsertQuery(result: { data: unknown; error: unknown }) {
  const query = {
    insert: vi.fn(),
    select: vi.fn(),
    single: vi.fn(),
  };

  query.insert.mockReturnValue(query);
  query.select.mockReturnValue(query);
  query.single.mockResolvedValue(result);

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
  mocks.getCurrentIdentity.mockResolvedValue(identity);
  mocks.canCreateWorkOrder.mockReturnValue(true);
});

describe("POST /api/work-orders", () => {
  test("returns 401 when no user is authenticated", async () => {
    mocks.getCurrentIdentity.mockResolvedValue(null);

    const response = await POST(
      createRequest({
        title: "AHU vibration",
        location: "Level 3 Plant Room",
      }),
    );

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({
      error: "Authentication is required.",
    });

    expect(mocks.canCreateWorkOrder).not.toHaveBeenCalled();
    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("returns 403 when the role cannot create work orders", async () => {
    mocks.canCreateWorkOrder.mockReturnValue(false);

    const response = await POST(
      createRequest({
        title: "AHU vibration",
        location: "Level 3 Plant Room",
      }),
    );

    expect(response.status).toBe(403);
    await expect(response.json()).resolves.toEqual({
      error: "Your role cannot create work orders.",
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
      body: { title: "   ", location: "Level 3 Plant Room" },
      caseName: "blank title",
    },
    {
      body: { title: "AHU vibration", location: "   " },
      caseName: "blank location",
    },
  ])("returns 400 for $caseName", async ({ body }) => {
    const response = await POST(createRequest(body));

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Title and location are required.",
    });

    expect(mocks.createClient).not.toHaveBeenCalled();
  });

  test("normalizes and inserts a valid work order", async () => {
    const workOrderInsert = createInsertQuery({
      data: createdOrder,
      error: null,
    });

    const activityInsert = vi.fn().mockResolvedValue({
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(workOrderInsert)
      .mockReturnValueOnce({
        insert: activityInsert,
      });

    mocks.createClient.mockResolvedValue({ from });

    const response = await POST(
      createRequest({
        title: "  AHU vibration  ",
        location: "  Level 3 Plant Room ",
        category_id: " ",
        priority: " HIGH ",
        description: " Abnormal vibration reported. ",
        contact_number: " ",
      }),
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({
      data: createdOrder,
    });

    expect(workOrderInsert.insert).toHaveBeenCalledWith({
      user_id: identity.userId,
      title: "AHU vibration",
      location: "Level 3 Plant Room",
      category_id: null,
      priority: "high",
      description: "Abnormal vibration reported.",
      submitted_by: identity.displayName,
      contact_number: null,
      status: "submitted",
    });

    expect(activityInsert).toHaveBeenCalledWith({
      user_id: identity.userId,
      work_order_id: createdOrder.id,
      action: "created",
      actor: identity.displayName,
      note: "Work order submitted.",
    });
  });

  test("defaults priority to medium", async () => {
    const workOrderInsert = createInsertQuery({
      data: {
        ...createdOrder,
        priority: "medium",
      },
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(workOrderInsert)
      .mockReturnValueOnce({
        insert: vi.fn().mockResolvedValue({ error: null }),
      });

    mocks.createClient.mockResolvedValue({ from });

    const response = await POST(
      createRequest({
        title: "AHU vibration",
        location: "Level 3 Plant Room",
      }),
    );

    expect(response.status).toBe(201);
    expect(workOrderInsert.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        priority: "medium",
      }),
    );
  });

  test("returns 400 when work-order insertion fails", async () => {
    const workOrderInsert = createInsertQuery({
      data: null,
      error: { message: "Insert failed" },
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(workOrderInsert),
    });

    const response = await POST(
      createRequest({
        title: "AHU vibration",
        location: "Level 3 Plant Room",
      }),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Insert failed",
    });
  });

  test("returns a generic creation error when insertion yields no data", async () => {
    const workOrderInsert = createInsertQuery({
      data: null,
      error: null,
    });

    mocks.createClient.mockResolvedValue({
      from: vi.fn().mockReturnValue(workOrderInsert),
    });

    const response = await POST(
      createRequest({
        title: "AHU vibration",
        location: "Level 3 Plant Room",
      }),
    );

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: "Unable to create work order.",
    });
  });

  test("deletes the created order when activity logging fails", async () => {
    const workOrderInsert = createInsertQuery({
      data: createdOrder,
      error: null,
    });

    const deleteQuery = createDeleteQuery({
      error: null,
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(workOrderInsert)
      .mockReturnValueOnce({
        insert: vi.fn().mockResolvedValue({
          error: { message: "Activity insert failed" },
        }),
      })
      .mockReturnValueOnce(deleteQuery);

    mocks.createClient.mockResolvedValue({ from });

    const response = await POST(
      createRequest({
        title: "AHU vibration",
        location: "Level 3 Plant Room",
      }),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Creation audit failed. The work order was not retained.",
    });

    expect(deleteQuery.delete).toHaveBeenCalled();
    expect(deleteQuery.eq).toHaveBeenCalledWith("id", createdOrder.id);
  });

  test("reports when activity logging and rollback both fail", async () => {
    const workOrderInsert = createInsertQuery({
      data: createdOrder,
      error: null,
    });

    const deleteQuery = createDeleteQuery({
      error: { message: "Rollback failed" },
    });

    const from = vi
      .fn()
      .mockReturnValueOnce(workOrderInsert)
      .mockReturnValueOnce({
        insert: vi.fn().mockResolvedValue({
          error: { message: "Activity insert failed" },
        }),
      })
      .mockReturnValueOnce(deleteQuery);

    mocks.createClient.mockResolvedValue({ from });

    const response = await POST(
      createRequest({
        title: "AHU vibration",
        location: "Level 3 Plant Room",
      }),
    );

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error:
        "Creation audit failed and the work order could not be removed automatically.",
    });
  });

  test("returns 500 for malformed JSON", async () => {
    const request = new Request("http://localhost/api/work-orders", {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: "{invalid-json",
    });

    const response = await POST(request);

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toEqual({
      error: "Internal server error",
    });
  });
});
