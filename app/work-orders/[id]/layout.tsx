import type { ReactNode } from "react";

// The contractor-CSV upload panel ("Contractor actual costs") used to be shown here for the
// assigned Technician. UAT 30 Oct 2026 retired it from the page: under D-22 the contractor's
// actual cost is the final contractor charge in Final Cost Reconciliation, backed by the
// attached quotation, and the optional itemised record is entered in the multi-line table.
// The component and its API route are kept, unused, until Stage 2 decides whether to bring back
// CSV import.
export default function WorkOrderFieldLayout({ children }: { children: ReactNode }) {
  return <>{children}</>;
}
