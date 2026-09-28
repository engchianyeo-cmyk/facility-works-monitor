import { beforeEach, describe, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";
const mocks=vi.hoisted(()=>({getCurrentIdentity:vi.fn(),createClient:vi.fn()}));
vi.mock("@/lib/auth",()=>({getCurrentIdentity:mocks.getCurrentIdentity}));vi.mock("@/lib/supabase/server",()=>({createClient:mocks.createClient}));
import { GET } from "@/app/api/incidents/[id]/route";
const context={params:Promise.resolve({id:"incident-id"})};
// Fluent Supabase test double intentionally models changing builder generics.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function chain(result:unknown){const q:any={};for(const m of ["select","eq","order"])q[m]=vi.fn(()=>q);q.maybeSingle=vi.fn(async()=>result);q.then=(resolve:(x:unknown)=>unknown)=>Promise.resolve(result).then(resolve);return q;}
beforeEach(()=>{vi.clearAllMocks();mocks.getCurrentIdentity.mockResolvedValue({userId:"admin",role:"administrator"});});
describe("GET /api/incidents/[id]",()=>{
  test("returns incident, safe assignment, SLA, timeline, work and notification summary",async()=>{const incident={id:"incident-id",reported_at:"2026-08-10T00:00:00Z",acknowledgement_deadline:"2026-08-10T00:05:00Z",acknowledged_at:null,assigned_technician:{id:"tech",display_name:"Tech",role:"technician"},assigned_team:null};const results=[chain({data:incident,error:null}),chain({data:[{id:"log"}],error:null}),chain({data:[{id:"wo"}],error:null}),chain({data:[{id:"n",channel:"sms",delivery_status:"failed"}],error:null})];mocks.createClient.mockResolvedValue({from:vi.fn(()=>results.shift())});const response=await GET(new NextRequest("http://localhost/api/incidents/incident-id"),context);expect(response.status).toBe(200);expect(await response.json()).toMatchObject({data:{incident:{id:"incident-id"},responder:{technician:{display_name:"Tech"}},activity:[{id:"log"}],linked_work_orders:[{id:"wo"}],notification_summary:{sms:{total:1,failed:1}}}});});
  test("does not expose raw detail transport errors",async()=>{mocks.createClient.mockResolvedValue({from:vi.fn(()=>chain({data:null,error:{message:"private"}}))});const response=await GET(new NextRequest("http://localhost/api/incidents/incident-id"),context);expect(response.status).toBe(500);expect(JSON.stringify(await response.json())).not.toContain("private");});
});
