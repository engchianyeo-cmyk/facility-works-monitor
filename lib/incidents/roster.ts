import { INCIDENT_TYPES, type IncidentType } from "@/lib/incidents/types";
import { UUID_PATTERN } from "@/lib/incidents/validation";

export type RosterPayload = { profile_id: string | null; team_id: string | null; receive_emergency_alerts: boolean; sms_enabled: boolean; whatsapp_enabled: boolean; escalation_order: number; active_from: string | null; active_to: string | null; incident_type: IncidentType | null; active: boolean };
export function validateRosterPayload(body: Record<string, unknown>): { value?: RosterPayload; error?: string } {
  const profileId=String(body.profile_id??"").trim()||null; const teamId=String(body.team_id??"").trim()||null;
  if ((profileId===null)===(teamId===null) || (profileId&&!UUID_PATTERN.test(profileId)) || (teamId&&!UUID_PATTERN.test(teamId))) return { error:"Select one valid Technician or maintenance team." };
  const order=Number(body.escalation_order??100); if(!Number.isInteger(order)||order<0||order>10000)return{error:"Escalation order must be an integer from 0 to 10000."};
  const type=String(body.incident_type??"").trim().toLowerCase()||null; if(type&&!INCIDENT_TYPES.includes(type as IncidentType))return{error:"Incident type is invalid."};
  const start=String(body.active_from??"").trim()||null; const end=String(body.active_to??"").trim()||null;
  if((start&&!Number.isFinite(Date.parse(start)))||(end&&!Number.isFinite(Date.parse(end)))||(start&&end&&Date.parse(end)<=Date.parse(start)))return{error:"Effective dates are invalid; end must be after start."};
  return { value:{profile_id:profileId,team_id:teamId,receive_emergency_alerts:body.receive_emergency_alerts!==false,sms_enabled:body.sms_enabled!==false,whatsapp_enabled:body.whatsapp_enabled!==false,escalation_order:order,active_from:start,active_to:end,incident_type:type as IncidentType|null,active:body.active!==false} };
}
