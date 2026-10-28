import { expect, test, type Page } from "@playwright/test";
import { login, logout, requiredEnvironment } from "./pilot-helpers";

/**
 * Work Order Lifecycle v2 acceptance (docs/design/WORK_ORDER_LIFECYCLE_V2.md):
 * Technician creates with quotation → Approver approves → Technician executes →
 * Supervisor approves as Completed → Technician uploads invoice → Finance receives and pays → Closed.
 * Decisions use the real screens; data entry that other suites already cover uses the same APIs the screens call.
 */
const technicianEmail = requiredEnvironment("E2E_TECHNICIAN_EMAIL");
const technicianPassword = requiredEnvironment("E2E_TECHNICIAN_PASSWORD");
const technician2Email = requiredEnvironment("E2E_TECHNICIAN2_EMAIL");
const technician2Password = requiredEnvironment("E2E_TECHNICIAN2_PASSWORD");
const approverEmail = requiredEnvironment("E2E_APPROVER_EMAIL");
const approverPassword = requiredEnvironment("E2E_APPROVER_PASSWORD");
const supervisorEmail = requiredEnvironment("E2E_SUPERVISOR_EMAIL");
const supervisorPassword = requiredEnvironment("E2E_SUPERVISOR_PASSWORD");
const financeEmail = requiredEnvironment("E2E_FINANCE_EMAIL");
const financePassword = requiredEnvironment("E2E_FINANCE_PASSWORD");
const baseRunId = requiredEnvironment("E2E_SYNTHETIC_RUN_ID").slice(0, 8);
const CONTRACTOR = "12a00000-0000-4000-8000-000000000001";
const PDF = Buffer.from("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n");
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jR1cAAAAASUVORK5CYII=", "base64");

async function workspace(page: Page, workOrderId: string, operation: string, payload: Record<string, unknown>) {
  const response = await page.request.post(`/api/work-orders/${workOrderId}/release-1`, { data: { operation, payload } });
  const body = await response.json();
  expect(response.ok(), `${operation}: ${body.message ?? ""}`).toBe(true);
  return body as Record<string, unknown>;
}

/** Submit the review and fail with the server's reason if it is refused (the timeline also shows the word "Completed"). */
async function reviewed(page: Page, button: ReturnType<Page["getByRole"]>) {
  const [response] = await Promise.all([
    page.waitForResponse((item) => item.url().includes("/transition") && item.request().method() === "POST", { timeout: 20_000 }),
    button.click(),
  ]);
  expect(response.ok(), `review: ${response.status()} ${await response.text()}`).toBe(true);
}

/** D-08: mark the location on the layout plan (API used by the markup editor) and add a Before photo on the screen. */
async function siteRequirements(page: Page, workOrderId: string, name: string) {
  await expect(page.getByText("Location marked on the layout plan").first()).toBeVisible();
  await workspace(page, workOrderId, "markup", { source_type: "drawing", source_reference: "FW-001", drawing_revision: "A (25 May 2024)", annotation_type: "marker", note: "Work location", geometry: { points: [{ x: 23.1, y: 37.4 }] } });
  const evidence = page.locator("section").filter({ has: page.getByRole("heading", { name: "Evidence" }) });
  await evidence.getByLabel("Category").selectOption("before");
  await evidence.getByLabel("Photo, video, voice recording or PDF", { exact: true }).setInputFiles({ name: `before-${name}.png`, mimeType: "image/png", buffer: PNG });
  await evidence.getByRole("button", { name: "Add evidence" }).click();
  await expect(evidence.getByText(`before-${name}.png`)).toBeVisible({ timeout: 20_000 });
}

/** datetime-local value for a time some hours ago (browser and runner share the local time zone). */
function hoursAgo(hours: number) {
  const date = new Date(Date.now() - hours * 3_600_000);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** D-11: the responsible Technician enters the actual work times on the screen. */
async function actualTimes(page: Page) {
  await page.getByLabel("Work started").fill(hoursAgo(4));
  await page.getByLabel("Work ended").fill(hoursAgo(1));
  await page.getByRole("button", { name: "Save work times" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Work times saved" })).toBeVisible({ timeout: 20_000 });
}

/** D-11: a second Technician of the facility endorses the Work Order before the Approver's review (facility default). */
async function endorsed(page: Page, workOrderPath: string) {
  await login(page, technician2Email, technician2Password, workOrderPath);
  await page.getByLabel("What did you check?").fill("Inspected the work on site and the photos; it is as recorded.");
  await page.getByRole("button", { name: "Endorse as authentic" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Endorsement recorded" })).toBeVisible({ timeout: 20_000 });
  await logout(page);
}

test.describe("Work Order Lifecycle v2", () => {
  test.setTimeout(240_000);

  test("Technician-created Work Order runs from quotation to Finance payment and closes", async ({ page }, testInfo) => {
    // A retry creates fresh records, so give them their own names (titles and invoice numbers stay unique).
    const runId = `${baseRunId}${testInfo.retry ? `r${testInfo.retry}` : ""}`;
    // 1. Technician creates the Draft.
    await login(page, technicianEmail, technicianPassword, "/work-orders/new");
    const form = page.locator("form").filter({ has: page.getByRole("button", { name: "Create Draft" }) });
    await form.locator('[name="title"]').fill(`Lifecycle v2 pump repair ${runId}`);
    await form.locator('[name="description"]').fill("Chilled water pump bearing noise; vibration rising for two weeks.");
    await form.locator('[name="location"]').fill("Utility Block chiller plant room");
    await page.getByRole("button", { name: "Create Draft" }).click();
    await expect(page).toHaveURL(/\/work-orders\/[0-9a-f-]+\?created=1#next-steps$/, { timeout: 20_000 });
    const workOrderPath = new URL(page.url()).pathname;
    const workOrderId = workOrderPath.split("/").pop()!;
    // D-10: the Draft is saved, shows the next steps and is listed under My Drafts.
    await expect(page.getByRole("heading", { name: "Draft saved — next steps" })).toBeVisible();
    await page.getByRole("link", { name: "My Drafts" }).first().click();
    await expect(page.getByRole("heading", { name: "My Drafts" })).toBeVisible();
    await page.getByRole("link", { name: new RegExp(`Lifecycle v2 pump repair ${runId}`) }).click();
    await expect(page).toHaveURL(new RegExp(`${workOrderPath}$`));
    await expect(page.getByText("Complete these items before submitting")).toBeVisible();
    await siteRequirements(page, workOrderId, runId);

    // 2. Quotation with the request (S$650, one quotation below the S$1,000 company threshold).
    const prepared = await workspace(page, workOrderId, "prepare_proposal", { vendor_id: CONTRACTOR, scope_summary: "Replace pump bearing and realign coupling.", proposed_amount: 650 });
    const quotationId = String((prepared.quotation as { id: string }).id);
    const upload = await page.request.post(`/api/work-orders/${workOrderId}/commercial-documents`, {
      multipart: { document_type: "quotation", record_id: quotationId, file: { name: `quotation-${runId}.pdf`, mimeType: "application/pdf", buffer: PDF } },
    });
    expect(upload.status(), `quotation upload: ${await upload.text()}`).toBe(201);
    await workspace(page, workOrderId, "submit_proposal", { quotation_id: quotationId, note: "Authentic contractor quotation" });
    await page.reload();
    await expect(page.getByText("Ready to submit for approval")).toBeVisible();
    await page.getByRole("button", { name: "Submit for approval" }).click();
    await expect(page.getByText("Awaiting Approval").first()).toBeVisible({ timeout: 20_000 });
    await logout(page);

    // 3. Approver (facility member, within S$250,000) approves work and quotation.
    await login(page, approverEmail, approverPassword, workOrderPath);
    await page.getByRole("button", { name: "Approve Work and Quotation" }).click();
    await page.getByLabel("Approval note (reason required for Administrator self-approval)").fill("Approved: within limit, quotation matches scope.");
    await page.getByRole("button", { name: "Confirm approval" }).click();
    await expect(page.getByText("Approved — Contractor to Proceed").first()).toBeVisible({ timeout: 20_000 });
    await logout(page);

    // 4. Technician witnesses and records the work.
    await login(page, technicianEmail, technicianPassword, workOrderPath);
    await page.getByRole("button", { name: "Start work" }).click();
    await expect(page.getByText("Work in Progress").first()).toBeVisible({ timeout: 20_000 });
    const evidence = page.locator("section").filter({ has: page.getByRole("heading", { name: "Evidence" }) });
    await evidence.getByLabel("Category").selectOption("after");
    await evidence.getByLabel("Photo, video, voice recording or PDF", { exact: true }).setInputFiles({ name: `after-${runId}.png`, mimeType: "image/png", buffer: PNG });
    await evidence.getByRole("button", { name: "Add evidence" }).click();
    await expect(evidence.getByText(`after-${runId}.png`)).toBeVisible({ timeout: 20_000 });
    await page.getByRole("button", { name: "Record Work Done" }).click();
    await page.getByLabel("Work performed statement").fill("Bearing replaced and coupling realigned; vibration normal.");
    await page.getByLabel("Cumulative labour hours").fill("3");
    await page.getByRole("button", { name: "Save Work Record" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Work record saved" })).toBeVisible();
    await workspace(page, workOrderId, "actual_cost", { cost_type: "service", description: "Contractor repair", unit: "job", quantity: 1, unit_rate: 620 });
    await page.reload();
    await page.getByRole("button", { name: "Confirm Actual Costing" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Actual costing confirmed" })).toBeVisible();
    // D-19/D-24: a variation order (S$620 against the S$650 quotation); the final cost and the contractor's revised
    // quotation go in with the submission for review, before the second Technician endorses (D-20).
    await workspace(page, workOrderId, "save_final_cost", { final_contractor_amount: 620, comments: "Final contractor account S$620.",
      variation_order: true, variation_justification: "Contractor reduced the labour after the site check." });
    const current = await (await page.request.get(`/api/work-orders/${workOrderId}/release-1`)).json();
    const finalUpload = await page.request.post(`/api/work-orders/${workOrderId}/commercial-documents`, {
      multipart: { document_type: "final_invoice", record_id: String(current.data.final_cost.id), file: { name: `final-quotation-${runId}.pdf`, mimeType: "application/pdf", buffer: PDF } },
    });
    expect(finalUpload.status(), `final quotation upload: ${await finalUpload.text()}`).toBe(201);
    await page.reload();
    await page.getByRole("button", { name: "Submit Physical Completion" }).click();
    await expect(page.getByText("Submitted for Review").first()).toBeVisible({ timeout: 20_000 });
    await actualTimes(page);
    await logout(page);
    await endorsed(page, workOrderPath);

    // 5. Supervisor approves work, final cost and documents → Completed.
    await login(page, supervisorEmail, supervisorPassword, workOrderPath);
    await expect(page.getByText("S$620.00").first()).toBeVisible();
    await page.getByRole("button", { name: "Approve as Completed" }).first().click();
    await page.getByLabel("Review note (required for a cost variance or Administrator self-review)").fill("Work, S$620 cost and evidence verified.");
    await reviewed(page, page.getByRole("button", { name: "Approve as Completed" }).last());
    await logout(page);

    // 6. Technician uploads the contractor invoice; the amount must equal S$620.
    await login(page, technicianEmail, technicianPassword, workOrderPath);
    await page.getByLabel("Contractor invoice (PDF/image)").setInputFiles({ name: `invoice-${runId}.pdf`, mimeType: "application/pdf", buffer: PDF });
    await page.getByLabel("Invoice number").fill(`INV-${runId}`);
    await page.getByLabel(/Invoice amount/).fill("650");
    await page.getByRole("button", { name: "Upload Invoice" }).click();
    await expect(page.getByText(/must equal the approved amount/)).toBeVisible({ timeout: 20_000 });
    await page.getByLabel("Contractor invoice (PDF/image)").setInputFiles({ name: `invoice-${runId}.pdf`, mimeType: "application/pdf", buffer: PDF });
    await page.getByLabel(/Invoice amount/).fill("620");
    await page.getByRole("button", { name: "Upload Invoice" }).click();
    await expect(page.getByText("Invoice uploaded. Finance and copied parties have been notified.")).toBeVisible({ timeout: 20_000 });
    await logout(page);

    // 7. Finance confirms receipt (payment terms start) and records payment → Closed.
    await login(page, financeEmail, financePassword, "/finance");
    await page.getByRole("link", { name: /Invoice uploaded/ }).click();
    const row = page.getByRole("row").filter({ hasText: `INV-${runId}` });
    await row.getByRole("link").first().click();
    await expect(page).toHaveURL(new RegExp(`${workOrderPath}$`));
    const today = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Singapore" }).format(new Date());
    await page.getByLabel("Date Finance received the invoice").fill(today);
    await page.getByRole("button", { name: "Confirm Invoice Received" }).click();
    await expect(page.getByText("Invoice receipt recorded")).toBeVisible({ timeout: 20_000 });
    const now = new Date(Date.now() + 8 * 3600_000).toISOString().slice(0, 16);
    await page.getByLabel("Paid on").fill(now);
    await page.getByLabel("Payment reference").fill(`PAY-${runId}`);
    await page.getByLabel("Finance note").fill("Paid per contractor terms.");
    await page.getByRole("button", { name: "Record Payment and Close" }).click();
    await expect(page.getByText(/^Closed$/).first()).toBeVisible({ timeout: 20_000 });
  });

  test("In-house Work Order follows the same approvals with pricing waived and closes at review (D-07)", async ({ page }, testInfo) => {
    // A retry creates fresh records, so give them their own names (titles and invoice numbers stay unique).
    const runId = `${baseRunId}${testInfo.retry ? `r${testInfo.retry}` : ""}`;
    await login(page, technicianEmail, technicianPassword, "/work-orders/new");
    const form = page.locator("form").filter({ has: page.getByRole("button", { name: "Create Draft" }) });
    await form.locator('[name="title"]').fill(`In-house repaint ${runId}`);
    await form.locator('[name="description"]').fill("Plant room door corroded; repaint by the in-house team.");
    await form.locator('[name="location"]').fill("Utility Block plant room door");
    await form.locator('[name="in_house_work"]').check();
    await page.getByRole("button", { name: "Create Draft" }).click();
    await expect(page).toHaveURL(/\/work-orders\/[0-9a-f-]+\?created=1#next-steps$/, { timeout: 20_000 });
    const workOrderPath = new URL(page.url()).pathname;
    await expect(page.getByRole("heading", { name: "In-House Services — Pricing Waived" })).toBeVisible();
    await siteRequirements(page, workOrderPath.split("/").pop()!, `ih-${runId}`);
    await page.reload();
    await expect(page.getByRole("button", { name: "Prepare Proposal" })).toHaveCount(0);
    await page.getByRole("button", { name: "Submit for approval" }).click();
    await expect(page.getByText("Awaiting Approval").first()).toBeVisible({ timeout: 20_000 });
    await logout(page);

    await login(page, approverEmail, approverPassword, workOrderPath);
    await page.getByRole("button", { name: "Approve Work and Quotation" }).click();
    await page.getByLabel("Approval note (reason required for Administrator self-approval)").fill("In-house repaint approved.");
    await page.getByRole("button", { name: "Confirm approval" }).click();
    await expect(page.getByText("Approved — Contractor to Proceed").first()).toBeVisible({ timeout: 20_000 });
    await logout(page);

    await login(page, technicianEmail, technicianPassword, workOrderPath);
    await page.getByRole("button", { name: "Start work" }).click();
    await expect(page.getByText("Work in Progress").first()).toBeVisible({ timeout: 20_000 });
    const evidence = page.locator("section").filter({ has: page.getByRole("heading", { name: "Evidence" }) });
    await evidence.getByLabel("Category").selectOption("after");
    await evidence.getByLabel("Photo, video, voice recording or PDF", { exact: true }).setInputFiles({ name: `repaint-${runId}.png`, mimeType: "image/png", buffer: PNG });
    await evidence.getByRole("button", { name: "Add evidence" }).click();
    await expect(evidence.getByText(`repaint-${runId}.png`)).toBeVisible({ timeout: 20_000 });
    await page.getByRole("button", { name: "Record Work Done" }).click();
    await page.getByLabel("Work performed statement").fill("Door sanded, primed and repainted by in-house staff.");
    await page.getByLabel("Cumulative labour hours").fill("2");
    await page.getByRole("button", { name: "Save Work Record" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Work record saved" })).toBeVisible();
    await page.getByRole("button", { name: "Confirm Actual Costing" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Actual costing confirmed" })).toBeVisible();
    await page.getByRole("button", { name: "Submit Physical Completion" }).click();
    await expect(page.getByText("Submitted for Review").first()).toBeVisible({ timeout: 20_000 });
    await actualTimes(page);
    await logout(page);
    await endorsed(page, workOrderPath);

    await login(page, supervisorEmail, supervisorPassword, workOrderPath);
    await expect(page.getByText("Not required — in-house services, pricing waived")).toBeVisible();
    await page.getByRole("button", { name: "Approve as Completed" }).first().click();
    await page.getByLabel("Review note (required for a cost variance or Administrator self-review)").fill("In-house repaint verified.");
    await reviewed(page, page.getByRole("button", { name: "Approve as Completed" }).last());
    await expect(page.getByText(/^Closed$/).first()).toBeVisible({ timeout: 20_000 });
  });
});
