import type { UserRole } from "@/lib/auth";
import InfoPanel from "@/components/ui/InfoPanel";
import MissionHeader from "./MissionHeader";
import SiteHealthCard from "./SiteHealthCard";
import CriticalIncidentPanel, { type MissionIncident } from "./CriticalIncidentPanel";
import EngineeringSystemsGrid from "./EngineeringSystemsGrid";
import OperationsSummary, { type MissionWorkOrder } from "./OperationsSummary";
import OperationalRiskPanel, { type OperationalRisk } from "./OperationalRiskPanel";
import PeopleOverview from "./PeopleOverview";
import TimelineFeed, { type TimelineItem } from "./TimelineFeed";
import CopilotPanel, { type MissionRecommendation } from "./CopilotPanel";
import QuickActions from "./QuickActions";
import FacilityLayoutPanel, { sampleFacilityLayoutConfig } from "./FacilityLayoutPanel";
import { roleLabel } from "@/lib/product-terminology";

export type MissionControlData = {
  identity: { displayName: string; role: UserRole; department: string | null };
  generatedAt: string;
  orders: MissionWorkOrder[];
  incidents: MissionIncident[];
  timeline: TimelineItem[];
  risks: OperationalRisk[];
  recommendations: MissionRecommendation[];
  kpis: { open: number; inProgress: number; pendingApproval: number; completed: number; dueToday: number; overdue: number; critical: number };
  people: { activeUsers: number | null; technicians: number | null; onCall: number | null; available: boolean };
  availability: { workOrders: boolean; incidents: boolean; timeline: boolean };
};

export default function MissionControl({ data }: { data: MissionControlData }) {
  const availabilityMessage = !data.availability.workOrders
    ? "Some Work Order information is temporarily unavailable. Incident operations remain available where shown."
    : "Some Incident information is temporarily unavailable. Work Order operations remain available.";

  return (
    <main className="mx-auto max-w-[1500px] space-y-6 p-4 sm:p-6 lg:p-8">
      <MissionHeader name={data.identity.displayName} role={roleLabel(data.identity.role)} department={data.identity.department} generatedAt={data.generatedAt} />
      {(!data.availability.workOrders || !data.availability.incidents) && <InfoPanel tone="warning" role="status">{availabilityMessage}</InfoPanel>}
      <SiteHealthCard activeIncidents={data.incidents.length} criticalOrders={data.kpis.critical} overdueOrders={data.kpis.overdue} dataAvailable={data.availability.workOrders} />
      <CriticalIncidentPanel incidents={data.incidents} available={data.availability.incidents} />
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.25fr)_minmax(20rem,.75fr)]">
        <OperationalRiskPanel risks={data.risks} />
        <CopilotPanel recommendations={data.recommendations} />
      </div>
      <EngineeringSystemsGrid open={data.kpis.open} inProgress={data.kpis.inProgress} pendingApproval={data.kpis.pendingApproval} completed={data.kpis.completed} dueToday={data.kpis.dueToday} />
      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(20rem,.65fr)]">
        <OperationsSummary orders={data.orders} />
        <div className="space-y-6">
          <PeopleOverview {...data.people} />
          <QuickActions role={data.identity.role} />
        </div>
      </div>
      <TimelineFeed items={data.timeline} />
      <FacilityLayoutPanel config={sampleFacilityLayoutConfig} />
    </main>
  );
}
